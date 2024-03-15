// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer, TransferLib} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IOfferLogic} from "@mgv-strats/src/strategies/interfaces/IOfferLogic.sol";

///@title `Direct` strats is an extension of MangroveOffer that allows contract's admin to manage offers on Mangrove.
abstract contract Direct is MangroveOffer {
  ///@notice address of the fund owner. Is used for the proxy owner if strat is using one.
  address public immutable FUND_OWNER;

  ///@notice whether this contract requires that routing pull orders provide *at most* the required amount.
  bool public immutable STRICT_PULLING;

  struct RouterParams {
    AbstractRouter routerImplementation; // 0x if not routing
    address fundOwner; // address must be controlled by msg.sender
    bool strict;
  }

  ///@notice `Direct`'s constructor.
  ///@param mgv The Mangrove deployment that is allowed to call `this` for trade execution and posthook.
  ///@param routerParams routing parameters. Use `noRouter()` to get an empty struct
  constructor(IMangrove mgv, RouterParams memory routerParams) MangroveOffer(mgv, routerParams.routerImplementation) {
    address fundOwner = routerParams.fundOwner == address(0) ? address(this) : routerParams.fundOwner;
    STRICT_PULLING = routerParams.strict;
    FUND_OWNER = fundOwner;
  }

  ///@notice convenience function to get an empty RouterParams struct
  ///@return an empty RouterParams struct
  function noRouter() public pure returns (RouterParams memory) {}

  ///@inheritdoc IOfferLogic
  ///@dev Returns the router to which pull/push calls must be done.
  ///@dev if strat is not routing, the call does not revert but returns a casted `address(0)`
  function router(address) public view virtual override returns (AbstractRouter) {
    return ROUTER_IMPLEMENTATION;
  }

  ///@notice convenience function
  ///@return the router to which pull/push calls must be done.
  function router() public view virtual returns (AbstractRouter) {
    return router(address(0));
  }

  ///@inheritdoc IOfferLogic
  ///@notice activates asset exchange with router
  function activate(IERC20 token) public virtual override {
    super.activate(token);
    if (_isRouting()) {
      require(TransferLib.approveToken(token, address(router()), type(uint).max), "Direct/RouterActivationFailed");
    }
  }

  /// @notice Inserts a new offer in Mangrove Offer List.
  /// @param args Function arguments stored in memory.
  /// @return offerId Identifier of the newly created offer. Returns 0 if offer creation was rejected by Mangrove and `args.noRevert` is set to `true`.
  /// @return status NEW_OFFER_SUCCESS if the offer was successfully posted on Mangrove. Returns Mangrove's revert reason otherwise.
  function _newOffer(OfferArgs memory args) internal returns (uint offerId, bytes32 status) {
    try MGV.newOfferByTick{value: args.fund}(args.olKey, args.tick, args.gives, args.gasreq, args.gasprice) returns (
      uint offerId_
    ) {
      offerId = offerId_;
      status = NEW_OFFER_SUCCESS;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      status = bytes32(bytes(reason));
    }
  }

  ///@inheritdoc MangroveOffer
  function _updateOffer(OfferArgs memory args, uint offerId) internal override returns (bytes32 status) {
    try MGV.updateOfferByTick{value: args.fund}(args.olKey, args.tick, args.gives, args.gasreq, args.gasprice, offerId)
    {
      status = REPOST_SUCCESS;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      status = bytes32(bytes(reason));
    }
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param olKey the offer list key.
  ///@param offerId the identifier of the offer in the offer list
  ///@param deprovision if set to `true` if offer admin wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function _retractOffer(
    OLKey memory olKey,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) internal returns (uint freeWei) {
    freeWei = MGV.retractOffer(olKey, offerId, deprovision);
  }

  ///@inheritdoc IOfferLogic
  function provisionOf(OLKey memory olKey, uint offerId) external view override returns (uint provision) {
    provision = _provisionOf(olKey, offerId);
  }

  ///@notice direct contract do not need to do anything specific with incoming funds during trade
  ///@dev one should override this function if one wishes to leverage taker's fund during trade execution
  ///@inheritdoc MangroveOffer
  function __put__(uint, MgvLib.SingleOrder calldata) internal virtual override returns (uint) {
    return 0;
  }

  ///@notice `__get__` hook for `Direct` is to ask the router to pull liquidity if using a router
  /// otherwise the function simply returns what's missing in the local balance
  ///@inheritdoc MangroveOffer
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    uint balance = IERC20(order.olKey.outbound_tkn).balanceOf(address(this));
    uint missing = balance >= amount ? 0 : amount - balance;
    if (!_isRouting()) {
      return missing;
    } else {
      uint pulled = router().pull(
        RL.RoutingOrder({
          token: IERC20(order.olKey.outbound_tkn),
          olKeyHash: order.olKey.hash(),
          offerId: order.offerId,
          fundOwner: FUND_OWNER
        }),
        missing,
        STRICT_PULLING
      );
      return pulled >= missing ? 0 : missing - pulled;
    }
  }

  ///@notice Flush outbound and inbound token back to the router (if any)
  ///@param order the order for which the flush is done
  function __routerFlush__(MgvLib.SingleOrder calldata order) internal virtual {
    if (_isRouting()) {
      bytes32 olKeyHash = order.olKey.hash();

      RL.RoutingOrder[] memory routingOrders = new RL.RoutingOrder[](2);
      routingOrders[0].token = IERC20(order.olKey.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
      routingOrders[0].fundOwner = FUND_OWNER;
      routingOrders[0].olKeyHash = olKeyHash;
      routingOrders[0].offerId = order.offerId;

      routingOrders[1].token = IERC20(order.olKey.inbound_tkn); // flushing liquidity brought by taker
      routingOrders[1].fundOwner = FUND_OWNER;
      routingOrders[1].olKeyHash = olKeyHash;
      routingOrders[1].offerId = order.offerId;

      router().flush(routingOrders);
    }
  }

  ///@notice Direct posthook flushes outbound and inbound token back to the router (if any)
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32)
  {
    __routerFlush__(order);
    // reposting offer residual if any
    return super.__posthookSuccess__(order, makerData);
  }
}
