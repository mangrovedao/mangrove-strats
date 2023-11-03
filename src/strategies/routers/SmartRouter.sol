// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "./abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

///@title Mangrove Smart Router implementation
contract SmartRouter is AbstractRouter {
  ///@notice logs new setting of routing logic for a specific offer
  ///@param token the asset whose route is being set
  ///@param olKeyHash the hash of the offer list
  ///@param offerId the offer identifier for which the routing is set
  ///@param logic the contract implementing the pull and push function for that specific route
  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRouter logic);

  ///@notice logics approved by admin in order to pull/push liquidity in an offer specific manner
  mapping(IERC20 token => mapping(bytes32 olKeyHash => mapping(uint offerId => AbstractRouter logic))) public
    routeLogics;

  struct OfferCoordinates {
    bytes32 olKeyHash; // (with offerId), offer specific route
    uint offerId;
  }

  ///@notice propagates revert occurring during a delegatecall
  ///@param retdata the return data of the delegatecall
  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("SmartRouter/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param oc Offer & market identifier
  ///@param logic the loggic to use for the given offer.
  function setLogic(IERC20 token, OfferCoordinates calldata oc, AbstractRouter logic) external onlyAdmin {
    routeLogics[token][oc.olKeyHash][oc.offerId] = logic;
    emit SetRouteLogic(token, oc.olKeyHash, oc.offerId, logic);
  }

  /// @inheritdoc AbstractRouter
  /// @dev pulls liquidity using the logic specified by offer owner
  /// @dev data must encode OfferCoordinates
  function __pull__(IERC20 token, uint amount, bytes memory data) internal virtual override returns (uint) {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    // note that rs.token is not considered since maker contract wants to pull `token` and owners approve logic globally (for all tokens)
    AbstractRouter logic = routeLogics[token][oc.olKeyHash][oc.offerId];
    if (address(logic) != address(0)) {
      // delegating routing to the specific chosen route
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.pull.selector, token, amount, bytes("")));
      if (!success) {
        revertWithData(retdata);
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
    AbstractRouter logic = routeLogics[token][oc.olKeyHash][oc.offerId];
    if (address(logic) != address(0)) {
      (bool success, bytes memory retdata) =
        address(logic).delegatecall(abi.encodeWithSelector(AbstractRouter.push.selector, token, amount, bytes("")));
      if (!success) {
        revertWithData(retdata);
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
    AbstractRouter logic = routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.balanceOfReserve(token, bytes(""));
  }

  ///@inheritdoc AbstractRouter
  ///@dev data must encode OfferCoordinates
  function __checkList__(IERC20 token, bytes calldata data) internal view override {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    require(token.allowance(admin(), address(this)) > 0, "SmartRouter/NotApprovedByOwner");
    AbstractRouter logic = routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.checkList(token, bytes(""));
  }

  ///@inheritdoc AbstractRouter
  ///@dev data must encode OfferCoordinates
  function __activate__(IERC20 token, bytes calldata data) internal override {
    OfferCoordinates memory oc = abi.decode(data, (OfferCoordinates));
    AbstractRouter logic = routeLogics[token][oc.olKeyHash][oc.offerId];
    return logic.activate(token, bytes(""));
  }
}
