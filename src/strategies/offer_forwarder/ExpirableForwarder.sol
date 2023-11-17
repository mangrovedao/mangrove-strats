// SPDX-License-Identifier:	BSD-2-Clause
import {
  MangroveOffer,
  Forwarder,
  IMangrove,
  RouterProxyFactory,
  AbstractRouter,
  MgvLib,
  IERC20,
  OLKey
} from "./abstract/Forwarder.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

pragma solidity ^0.8.10;

///@title Forwarder than enables expiry dates for the offer it posts. Expiry is tested in `__lastLook__` hook and induces a small bounty for offer owner.
contract ExpirableForwarder is Forwarder {
  ///@notice Same as Forwarder's constructor
  ///@param mgv the deployed Mangrove contract on which this contract will post offers.
  ///@param factory the router proxy factory contract -- cannot be 0x
  ///@param routerImplementation the deployed SmartRouter contract used to generate proxys for offer owners -- cannot be 0x
  constructor(IMangrove mgv, RouterProxyFactory factory, AbstractRouter routerImplementation)
    Forwarder(mgv, factory, routerImplementation)
  {}

  ///@notice The expiry of the offer has been set
  ///@param olKeyHash the hash of the offer list key. It is indexed so RPC call can filter on it.
  ///@param offerId the Mangrove offer id.
  ///@param date in seconds since unix epoch
  ///@notice By emitting this data, an indexer will be able to keep track of the expiry date of an offer.
  event SetExpiry(bytes32 indexed olKeyHash, uint indexed offerId, uint date);

  ///@notice `_expiryMaps[olKey.hash()][offerId]` gives timestamp beyond which `offerId` on the `olKey.(outbound_tkn, inbound_tkn, tickSpacing)` offer list should renege on trade.
  ///@notice if the order tx is included after the expiry date, it reverts.
  ///@dev 0 means no expiry.
  mapping(bytes32 olKeyHash => mapping(uint offerId => uint expiry)) private _expiryMaps;

  ///@notice returns expiry date of an offer
  ///@param olKeyHash the identifier of the offer list
  ///@param offerId the offer identifier
  ///@return expiry date
  function expiring(bytes32 olKeyHash, uint offerId) external view returns (uint) {
    return _expiryMaps[olKeyHash][offerId];
  }

  ///@notice Updates the expiry date for a specific offer.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The offer id whose expiry date is to be set.
  ///@param expiryDate in seconds since unix epoch
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  function setExpiry(bytes32 olKeyHash, uint offerId, uint expiryDate) public onlyOwner(olKeyHash, offerId) {
    _expiryMaps[olKeyHash][offerId] = expiryDate;
    emit SetExpiry(olKeyHash, offerId, expiryDate);
  }

  ///Checks the current timestamps and reneges on trade (by reverting) if the offer has expired.
  ///@inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32) {
    uint exp = _expiryMaps[order.olKey.hash()][order.offerId];
    require(exp == 0 || block.timestamp <= exp, "ExpirableForwarder/expired");
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

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param olKey the offer list key.
  ///@param offerId the identifier of the offer in the offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision)
    public
    onlyOwner(olKey.hash(), offerId)
    returns (uint freeWei)
  {
    return _retractOffer(olKey, offerId, deprovision);
  }
}
