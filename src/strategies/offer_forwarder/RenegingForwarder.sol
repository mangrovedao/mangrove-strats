// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {
  MangroveOffer,
  Forwarder,
  IMangrove,
  RouterProxyFactory,
  RouterProxy,
  AbstractRouter,
  MgvLib,
  IERC20,
  OLKey
} from "./abstract/Forwarder.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

///@title Forwarder contract with basic functionality
///@notice This contract can be used to post and update offers on Mangrove on behalf of a user. Users can also retract their offers and set/update their expiry.
///@dev Reneging of offers relies on the `__lastLook__` hook of the `MangroveOffer` contract which reverts when some predicate over timestamp and received order is met.
contract RenegingForwarder is Forwarder {
  ///@notice Same as Forwarder's constructor
  ///@param mgv the deployed Mangrove contract on which this contract will post offers -- will revert if 0x
  ///@param factory the router proxy factory contract -- will revert if 0x
  ///@param routerImplementation the deployed SmartRouter contract used to generate proxys for offer owners -- will revert if 0x
  constructor(IMangrove mgv, RouterProxyFactory factory, AbstractRouter routerImplementation)
    Forwarder(mgv, factory, routerImplementation)
  {}

  ///@notice The expiry and max volume of the offer has been set
  ///@param olKeyHash the hash of the offer list key. It is indexed so RPC call can filter on it.
  ///@param offerId the Mangrove offer id.
  ///@param date in seconds since unix epoch
  ///@param volume the amount of outbound tokens above which the offer should renege on trade.
  ///@notice By emitting this data, an indexer will be able to keep track of the expiry date and the max volume of an offer.
  event SetReneging(bytes32 indexed olKeyHash, uint indexed offerId, uint date, uint volume);

  struct Condition {
    uint160 date;
    uint96 volume;
  }

  ///@notice `__renegeMap[olKey.hash()][offerId]` gives timestamp beyond which `offerId` on the `olKey.(outbound_tkn, inbound_tkn, tickSpacing)` offer list should renege on trade.
  ///@notice They also give the max volume of tokens upon which the offer should renege on trade.
  ///@notice if the order tx is included after the expiry date, it reverts.
  ///@dev 0 means no expiry and no max volume.
  mapping(bytes32 olKeyHash => mapping(uint offerId => Condition)) private __renegeMap;

  ///@notice returns expiry date and max volume of an offer
  ///@param olKeyHash the identifier of the offer list
  ///@param offerId the offer identifier
  ///@return expiry date and max Volume
  function reneging(bytes32 olKeyHash, uint offerId) public view returns (Condition memory) {
    return __renegeMap[olKeyHash][offerId];
  }

  ///@notice Updates the expiry date and the max volume for a specific offer if caller is the offer owner.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The offer id whose expiry date and max volume is to be set.
  ///@param expiryDate in seconds since unix epoch. Use 0 for no expiry.
  ///@param volume the amount of outbound tokens above which the offer should renege on trade.
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  /// * While updating, the volume should be set to 0. Otherwise, we create a renege for no reason.
  /// * If the user wants to reduce the promised volume, he should update his offer directly.
  /// * If we had to use max volume to avoid reneging with minimum volume, the user could update the offer by himself and set volume back to 0.
  function setReneging(bytes32 olKeyHash, uint offerId, uint expiryDate, uint volume)
    external
    onlyOwner(olKeyHash, offerId)
  {
    _setReneging(olKeyHash, offerId, expiryDate, volume);
  }

  ///@notice internal version of the above.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The offer id whose expiry date and max volume is to be set.
  ///@param expiryDate in seconds since unix epoch. Use 0 for no expiry.
  ///@param volume the amount of outbound tokens above which the offer should renege on trade.
  function _setReneging(bytes32 olKeyHash, uint offerId, uint expiryDate, uint volume) internal {
    Condition memory cond;
    cond.date = uint160(expiryDate);
    require(cond.date == expiryDate, "RenegingForwarder/dateOverflow");
    cond.volume = uint96(volume);
    require(cond.volume == volume, "RenegingForwarder/volumeOverflow");
    __renegeMap[olKeyHash][offerId] = cond;
    emit SetReneging(olKeyHash, offerId, expiryDate, volume);
  }

  ///@inheritdoc MangroveOffer
  ///@dev making sure offer does not over promise twice when reposting offer residual.
  function __residualValues__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint newGives, Tick newTick)
  {
    Condition memory cond = __renegeMap[order.olKey.hash()][order.offerId];
    if (cond.volume == 0) {
      return super.__residualValues__(order);
    } else {
      // new volume to be offered
      // if __residualValues__ is called in __posthookFallback__ the offer reneged and cond.volume could be higher than takerWants
      newGives = order.takerWants < cond.volume ? cond.volume - order.takerWants : 0;
      // same price
      newTick = order.offer.tick();
    }
  }

  ///@inheritdoc MangroveOffer
  ///@notice Checks the current timestamps and `order.takerWants` and reneges on trade (by reverting) if the offer has expired or order is over sized.
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32) {
    bytes32 olKeyHash = order.olKey.hash();
    Condition memory cond = __renegeMap[olKeyHash][order.offerId];

    require(cond.date == 0 || block.timestamp < uint(cond.date), "RenegingForwarder/expired");
    require(cond.volume == 0 || order.takerWants <= uint(cond.volume), "RenegingForwarder/overSized");

    return super.__lastLook__(order);
  }

  ///@notice updates an offer on Mangrove
  ///@dev this can be used to update price of the resting order
  ///@param olKey the offer list key.
  ///@param tick the tick
  ///@param gives new amount of `olKey.outbound_tkn` offer owner gives
  ///@param gasreq new gas req for the restingOrder
  ///@param offerId the id of the offer to be updated
  function updateOffer(OLKey memory olKey, Tick tick, uint gives, uint gasreq, uint offerId)
    external
    payable
    onlyOwner(olKey.hash(), offerId)
  {
    OfferArgs memory args;

    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    args.fund = msg.value;
    args.olKey = olKey;
    args.tick = tick;
    args.gives = gives;
    args.gasreq = gasreq;
    args.noRevert = false; // will throw if Mangrove reverts
    _updateOffer(args, offerId);
  }

  ///@inheritdoc MangroveOffer
  function _updateOffer(OfferArgs memory args, uint offerId) internal override returns (bytes32 reason) {
    Condition memory cond = reneging(args.olKey.hash(), offerId);
    if (cond.volume > 0) {
      // resetting volume to 0 when updating offer
      // When reposting on partial fill, residual values are computed based on the reneging volume.
      // So new we can safely set back the max volume to 0.
      _setReneging(args.olKey.hash(), offerId, cond.date, 0);
    }
    return super._updateOffer(args, offerId);
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param olKey the offer list key.
  ///@param offerId the identifier of the offer in the offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision)
    external
    onlyOwner(olKey.hash(), offerId)
    returns (uint freeWei)
  {
    (freeWei,) = _retractOffer(olKey, offerId, false, deprovision);
    if (freeWei > 0) {
      (bool noRevert,) = msg.sender.call{value: freeWei}("");
      require(noRevert, "RenegingForwarder/weiTransferFail");
    }
  }
}
