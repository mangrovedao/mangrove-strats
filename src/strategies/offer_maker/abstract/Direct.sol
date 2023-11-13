// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer, TransferLib, SmartRouterProxy} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IOfferLogic} from "@mgv-strats/src/strategies/interfaces/IOfferLogic.sol";

///@title `Direct` strats is an extension of MangroveOffer that allows contract's admin to manage offers on Mangrove.
abstract contract Direct is MangroveOffer {
  /// @notice router proxy contract (can be 0x if this contract does not user liquidity routing)
  SmartRouterProxy public immutable ROUTER_PROXY;

  ///@notice address of the proxy owner (that determines router proxy's address if routing is required).
  address public immutable PROXY_OWNER;

  ///@notice whether this contract requires routing pull orders to provide at most routing amount.
  bool public immutable STRICT_PULLING;

  struct RouterParams {
    AbstractRouter routerImplementation;
    address proxyOwner;
    bool strict;
  }

  ///@notice `Direct`'s constructor.
  ///@param mgv The Mangrove deployment that is allowed to call `this` for trade execution and posthook.
  ///@param routerImplementation the router that this contract will use to pull/push liquidity from offer maker's reserve. This can be `address(0)` if no liquidity routing will ever be enabled.
  ///@param proxyOwner address to be used to determine router proxy address (when one is required) to be used to route liquidity for this contract.
  ///@param strict whether routing pull order are required to provide at most pull amount (ignored if `routerImplementation == address(0)`).
  ///@dev if `proxyOwner` already has a router proxy deployed, it must bind it to this contract at the end of that constructor.
  constructor(IMangrove mgv, RouterParams memory routerParams) MangroveOffer(mgv, routerParams.routerImplementation) {
    // proxyOwner != this ==> routerImpl != 0x
    require(
      routerParams.proxyOwner == address(this) || address(routerParams.routerImplementation) != address(0),
      "Direct/0xRouterImplementation"
    );
    // proxyOwner == 0x => routerImpl == 0x
    require(
      routerParams.proxyOwner != address(0) || address(routerParams.routerImplementation) == address(0),
      "Direct/0xProxyOwner"
    );
    if (routerParams.routerImplementation != AbstractRouter(address(0))) {
      (ROUTER_PROXY,) = deployRouterIfNeeded(routerParams.proxyOwner);
      PROXY_OWNER = routerParams.proxyOwner;
      STRICT_PULLING = routerParams.strict;
    } else {
      ROUTER_PROXY = SmartRouterProxy(address(0));
    }
  }

  ///@notice whether this contract has enabled liquidity routing
  function isRouting() public view returns (bool) {
    address(ROUTER_PROXY).code.length > 0;
  }

  function noRouter() internal pure returns (RouterParams memory) {}

  ///@inheritdoc IOfferLogic
  ///@notice activates asset exchange with router
  function activate(IERC20 token) public virtual override {
    super.activate(token);
    if (isRouting()) {
      require(TransferLib.approveToken(token, address(ROUTER_PROXY), type(uint).max), "Direct/RouterActivationFailed");
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
    uint missing = super.__get__(amount, order);
    if (!isRouting()) {
      return missing;
    } else {
      uint pulled = AbstractRouter(address(ROUTER_PROXY)).pull(
        RL.RoutingOrder({
          token: IERC20(order.olKey.outbound_tkn),
          amount: missing,
          olKeyHash: order.olKey.hash(),
          offerId: order.offerId,
          reserveId: PROXY_OWNER
        }),
        STRICT_PULLING
      );
      return pulled >= missing ? 0 : missing - pulled;
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
    if (isRouting()) {
      RL.RoutingOrder[] memory routingOrders = new RL.RoutingOrder[](2);
      routingOrders[0].token = IERC20(order.olKey.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
      routingOrders[0].amount = IERC20(order.olKey.outbound_tkn).balanceOf(address(this));
      routingOrders[0].reserveId = PROXY_OWNER;

      routingOrders[1].token = IERC20(order.olKey.inbound_tkn); // flushing liquidity brought by taker
      routingOrders[1].amount = IERC20(order.olKey.inbound_tkn).balanceOf(address(this));
      routingOrders[1].reserveId = PROXY_OWNER;

      AbstractRouter(address(ROUTER_PROXY)).flush(routingOrders);
    }
    // reposting offer residual if any
    return super.__posthookSuccess__(order, makerData);
  }
}
