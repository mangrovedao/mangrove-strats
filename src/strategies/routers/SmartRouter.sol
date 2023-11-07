// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {SmartRouterStorage, AbstractRouter, IERC20} from "./SmartRouterStorage.sol";
import {SimpleRouter, RL} from "./SimpleRouter.sol";

///@title Mangrove Smart Router implementation
contract SmartRouter is SimpleRouter {
  ///@notice logs new setting of routing logic for a specific offer
  ///@param token the asset whose route is being set
  ///@param olKeyHash the hash of the offer list
  ///@param offerId the offer identifier for which the routing is set
  ///@param logic the contract implementing the pull and push function for that specific route
  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRouter logic);

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param token the asset for which the routing logic should be set.
  ///@param olKeyHash market identifier
  ///@param offerId offer identifier
  ///@param logic the loggic to use for the given offer.
  function setLogic(IERC20 token, bytes32 olKeyHash, uint offerId, AbstractRouter logic) external onlyAdmin {
    SmartRouterStorage.getStorage().routeLogics[token][olKeyHash][offerId] = logic;
    emit SetRouteLogic(token, olKeyHash, offerId, logic);
  }

  /// @inheritdoc AbstractRouter
  /// @dev pulls liquidity using the logic specified by offer owner
  function __pull__(RL.RoutingOrder memory routingOrder, bool strict) internal virtual override returns (uint) {
    AbstractRouter logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      // delegating routing to the specific chosen route
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.pull.selector, routingOrder, strict));
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      return (abi.decode(retdata, (uint)));
    } else {
      // default route is to pull funds directly from `routingOrder.reserveId`
      return super.__pull__(routingOrder, strict);
    }
  }

  /// @inheritdoc AbstractRouter
  /// @dev pushes liquidity using the logic specified by offer owner
  function __push__(RL.RoutingOrder memory routingOrder) internal virtual override returns (uint) {
    AbstractRouter logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.push.selector, routingOrder));
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      return (abi.decode(retdata, (uint)));
    } else {
      return super.__push__(routingOrder);
    }
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(RL.RoutingOrder calldata routingOrder) public view override returns (uint) {
    AbstractRouter logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) = address(this).staticcall(
        abi.encodeWithSelector(
          SmartRouterStorage._staticdelegatecall.selector,
          abi.encodeWithSelector(AbstractRouter.balanceOfReserve.selector, routingOrder)
        )
      );
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      return (abi.decode(retdata, (uint)));
    } else {
      return super.balanceOfReserve(routingOrder);
    }
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(RL.RoutingOrder calldata routingOrder) internal view override {
    AbstractRouter logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) = address(this).staticcall(
        abi.encodeWithSelector(
          SmartRouterStorage._staticdelegatecall.selector,
          abi.encodeWithSelector(AbstractRouter.checkList.selector, routingOrder)
        )
      );
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
    } else {
      super.__checkList__(routingOrder);
    }
  }

  ///@inheritdoc AbstractRouter
  function __activate__(RL.RoutingOrder calldata routingOrder) internal override {
    AbstractRouter logic =
      SmartRouterStorage.getStorage().routeLogics[routingOrder.token][routingOrder.olKeyHash][routingOrder.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.activate.selector, routingOrder));
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
    } else {
      super.__activate__(routingOrder);
    }
  }
}
