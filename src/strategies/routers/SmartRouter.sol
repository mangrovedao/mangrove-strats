// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {SmartRouterStorage, AbstractRouter, IERC20} from "./SmartRouterStorage.sol";

///@title Mangrove Smart Router implementation
contract SmartRouter is AbstractRouter {
  ///@notice logs new setting of routing logic for a specific offer
  ///@param token the asset whose route is being set
  ///@param olKeyHash the hash of the offer list
  ///@param offerId the offer identifier for which the routing is set
  ///@param logic the contract implementing the pull and push function for that specific route
  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRouter logic);

  struct OfferCoordinates {
    bytes32 olKeyHash; // (with offerId), offer specific route
    uint offerId;
  }

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param token the asset for which the routing logic should be set.
  ///@param oc Offer & market identifier
  ///@param logic the loggic to use for the given offer.
  function setLogic(IERC20 token, OfferCoordinates calldata oc, AbstractRouter logic) external onlyAdmin {
    SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId] = logic;
    emit SetRouteLogic(token, oc.olKeyHash, oc.offerId, logic);
  }

  /// @inheritdoc AbstractRouter
  /// @dev pulls liquidity using the logic specified by offer owner
  /// @dev data must encode OfferCoordinates
  function __pull__(IERC20 token, uint amount, bytes memory data) internal virtual override returns (uint) {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    AbstractRouter logic = SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId];
    if (address(logic) != address(0)) {
      // delegating routing to the specific chosen route
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.pull.selector, token, amount, bytes("")));
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      require(abi.decode(retdata, (uint)) == amount, "SmartRouter/partialPullNotAllowed");
    } else {
      // default route
      require(TransferLib.transferTokenFrom(token, admin(), msg.sender, amount), "SmartRouter/DefaultPullFailed");
    }
    return amount;
  }

  /// @inheritdoc AbstractRouter
  /// @dev pushes liquidity using the logic specified by offer owner
  /// @dev data must encode OfferCoordinates
  function __push__(IERC20 token, uint amount, bytes memory data) internal virtual override returns (uint pushed) {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    AbstractRouter logic = SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.push.selector, token, amount, bytes("")));
      if (!success) {
        SmartRouterStorage.revertWithData(retdata);
      }
      require(abi.decode(retdata, (uint)) == amount, "SmartRouter/partialPushNotAllowed");
    } else {
      require(TransferLib.transferTokenFrom(token, msg.sender, admin(), amount), "SmartRouter/DefaultPushFailed");
    }
    return amount;
  }

  ///@inheritdoc AbstractRouter
  ///@dev data must encode OfferCoordinates
  function balanceOfReserve(IERC20 token, bytes calldata data) public view override returns (uint) {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    AbstractRouter logic = SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.balanceOfReserve(token, bytes(""));
  }

  ///@inheritdoc AbstractRouter
  ///@dev data must encode OfferCoordinates
  function __checkList__(IERC20 token, bytes calldata data) internal view override {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    require(token.allowance(admin(), address(this)) > 0, "SmartRouter/NotApprovedByOwner");
    AbstractRouter logic = SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.checkList(token, bytes(""));
  }

  ///@inheritdoc AbstractRouter
  ///@dev data must encode OfferCoordinates
  function __activate__(IERC20 token, bytes calldata data) internal override {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    AbstractRouter logic = SmartRouterStorage.getStorage().routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.activate(token, bytes(""));
  }
}
