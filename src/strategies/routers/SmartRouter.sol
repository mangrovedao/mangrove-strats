// SPDX-License-Identifier:	MIT
pragma solidity ^0.8.18;

import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {SmartRouterStorage, AbstractRoutingLogic, IERC20} from "./SmartRouterStorage.sol";
import {AbstractRouter, SimpleRouter, RL} from "./SimpleRouter.sol";

///@title Mangrove Smart Router implementation
///@notice Router delegates pull and push logic implementation to arbitrary contracts that implement the `AbstractRoutingLogic` interface.
contract SmartRouter is SimpleRouter {
  /// @notice This value is a forced binding, It will be mainly used to refer to the `MangroveOrder` contract.
  /// * this will allow making a single transaction to deploy, bind and take an offer at the same time with the most common strategy.
  address public immutable forcedBinding;

  /// @notice Contract's constructor
  /// @param _forcedBinding the address of the contract that will be forced to be bound to this router.
  constructor(address _forcedBinding) {
    forcedBinding = _forcedBinding;
  }

  /// @inheritdoc AbstractRouter
  function isBound(address mkr) public view virtual override returns (bool) {
    return mkr == forcedBinding || super.isBound(mkr);
  }

  ///@notice logs new setting of routing logic for a specific offer
  ///@param token the asset whose route is being set
  ///@param olKeyHash the hash of the offer list
  ///@param offerId the offer identifier for which the routing is set
  ///@param logic the contract implementing the pull and push function for that specific route
  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRoutingLogic logic);

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param routingOrder the routing order template for which a logic should be used
  ///@param logic the logic to use for the given offer.xw
  ///@dev `routingOrder.reserveId` is ignored as there is a unique mapping in storage per `reserveId`
  function setLogic(RL.RoutingOrder calldata routingOrder, AbstractRoutingLogic logic) external boundOrAdmin {
    SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId] =
      logic;
    emit SetRouteLogic(routingOrder.token, routingOrder.olKeyHash, routingOrder.offerId, logic);
  }

  ///@notice This function is used to get the routing strategy for a given offer.
  ///@param routingOrder the routing order template for which a logic should be used
  ///@return logic the logic used for the given routing order.
  function getLogic(RL.RoutingOrder calldata routingOrder) external view returns (AbstractRoutingLogic) {
    return SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
  }

  /// @inheritdoc AbstractRouter
  /// @dev pulls liquidity using the logic specified by offer owner
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint)
  {
    AbstractRoutingLogic logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      // delegating routing to the specific chosen route
      (bool success, bytes memory retdata) = address(logic).delegatecall(
        abi.encodeWithSelector(
          AbstractRoutingLogic.pullLogic.selector, routingOrder.token, routingOrder.fundOwner, amount, strict
        )
      );
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      return (abi.decode(retdata, (uint)));
    } else {
      // default route is to pull funds directly from `routingOrder.fundOwner`
      return super.__pull__(routingOrder, amount, strict);
    }
  }

  /// @inheritdoc AbstractRouter
  /// @dev pushes liquidity using the logic specified by offer owner
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal virtual override returns (uint) {
    AbstractRoutingLogic logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) = address(logic).delegatecall(
        abi.encodeWithSelector(
          AbstractRoutingLogic.pushLogic.selector, routingOrder.token, routingOrder.fundOwner, amount
        )
      );
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      return (abi.decode(retdata, (uint)));
    } else {
      return super.__push__(routingOrder, amount);
    }
  }

  ///@inheritdoc AbstractRouter
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint) {
    AbstractRoutingLogic customLogic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(customLogic) != address(0)) {
      return customLogic.balanceLogic(routingOrder.token, routingOrder.fundOwner);
    } else {
      return super.tokenBalanceOf(routingOrder);
    }
  }
}
