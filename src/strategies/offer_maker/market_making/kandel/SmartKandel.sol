// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer, RL} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

///@title The SmartKandel strat with geometric price progression.
contract SmartKandel is GeometricKandel {
  ///@notice The factory for creating router proxies.
  RouterProxyFactory public immutable PROXY_FACTORY;

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param owner the owner of the strat
  ///@param factory the router proxy factory contract.
  ///@param routerImplementation the deployed SmartRouter contract used to generate proxys for offer owners.
  constructor(
    IMangrove mgv,
    OLKey memory olKeyBaseQuote,
    uint gasreq,
    address owner,
    RouterProxyFactory factory,
    AbstractRouter routerImplementation
  )
    GeometricKandel(
      mgv,
      olKeyBaseQuote,
      RouterParams({
        routerImplementation: AbstractRouter(factory.computeProxyAddress(owner, routerImplementation)),
        fundOwner: owner,
        strict: true
      })
    )
  {
    setGasreq(gasreq);
    activate(BASE);
    activate(QUOTE);
    PROXY_FACTORY = factory;
    factory.instantiate(owner, routerImplementation);
  }

  ///@notice convenience function to the id for kandel
  ///@return kandelID the id for kandel
  function _kandelID() internal view returns (bytes32 kandelID) {
    assembly {
      kandelID := address()
    }
  }

  /// @notice Returns the routing order for this contract
  /// @return routingOrder the routing order for this contract
  function _routingOrder() internal view returns (RL.RoutingOrder memory routingOrder) {
    routingOrder.fundOwner = FUND_OWNER;
    routingOrder.olKeyHash = _kandelID();
  }

  ///@notice sets the routing logics for the router
  ///@param baseLogic the logic for the base token
  ///@param quoteLogic the logic for the quote token
  ///@param gasreq the gasreq to use for offers (0 if unchanged)
  function setLogics(AbstractRoutingLogic baseLogic, AbstractRoutingLogic quoteLogic, uint gasreq) public onlyAdmin {
    SmartRouter _router = SmartRouter(address(router()));

    RL.RoutingOrder memory routingOrder = _routingOrder();
    routingOrder.token = BASE;
    _router.setLogic(routingOrder, baseLogic);
    routingOrder.token = QUOTE;
    _router.setLogic(routingOrder, quoteLogic);

    if (gasreq > 0) {
      setGasreq(gasreq);
    }
  }

  ///@inheritdoc MangroveOffer
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint missing) {
    uint balance = IERC20(order.olKey.outbound_tkn).balanceOf(address(this));
    missing = balance >= amount ? 0 : amount - balance;
    if (missing > 0) {
      RL.RoutingOrder memory routingOrder = _routingOrder();
      routingOrder.token = IERC20(order.olKey.outbound_tkn);
      uint pulled = router().pull(routingOrder, missing, STRICT_PULLING);
      return pulled >= missing ? 0 : missing - pulled;
    }
  }

  ///@inheritdoc Direct
  function __routerFlush__(MgvLib.SingleOrder calldata order) internal override {
    bytes32 kandelID = _kandelID();

    RL.RoutingOrder[] memory routingOrders = new RL.RoutingOrder[](2);
    routingOrders[0].token = IERC20(order.olKey.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
    routingOrders[0].fundOwner = FUND_OWNER;
    routingOrders[0].olKeyHash = kandelID;

    routingOrders[1].token = IERC20(order.olKey.inbound_tkn); // flushing liquidity brought by taker
    routingOrders[1].fundOwner = FUND_OWNER;
    routingOrders[1].olKeyHash = kandelID;

    router().flush(routingOrders);
  }

  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32 repostStatus)
  {
    transportSuccessfulOrder(order);
    repostStatus = super.__posthookSuccess__(order, makerData);
  }
}
