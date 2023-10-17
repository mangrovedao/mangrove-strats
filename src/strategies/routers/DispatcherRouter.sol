// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {MonoRouter, AbstractRouter} from "./abstract/MonoRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

///@title `MultiRouter` instances may have token and reserveId dependant sourcing strategies.
contract DispatcherRouter is AbstractRouter {
  ///@notice logs new routes and route updates.
  ///@dev TODO: set router to type of strategy.
  event SetRoute(address indexed owner, IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, address router);

  ///@notice the specific route to use
  mapping(
    address owner => mapping(IERC20 token => mapping(bytes32 olKeyHash => mapping(uint offerId => address router)))
  ) public routes;

  struct PullStruct {
    address owner;
    address caller;
    bytes32 olKeyHash;
    uint offerId;
  }

  struct PushStruct {
    address owner;
  }

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 token, address reserveId) internal view override returns (uint) {
    revert("DispatcherRouter/NotImplemented");
  }

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param token the token that the offer is for.
  ///@param olKeyHash the olKeyHash that the offer is for.
  ///@param offerId the offerId that the offer is for.
  ///@param router the router to use for the given offer.
  function setRoute(IERC20 token, bytes32 olKeyHash, uint offerId, address router) external {
    routes[msg.sender][token][olKeyHash][offerId] = router;
    emit SetRoute(msg.sender, token, olKeyHash, offerId, router);
  }

  function executeTransfer(IERC20 underlying, IERC20 overlying, uint amount, PullStruct calldata offer) external {
    address route = routes[offer.owner][underlying][offer.olKeyHash][offer.offerId];
    require(route == msg.sender, "DispatcherRouter/InvalidAccess");
    require(
      TransferLib.transferTokenFrom(overlying, offer.owner, msg.sender, amount), "DispatcherRouter/TransferFailed"
    );
  }

  function __pull__(IERC20 token, uint amount, bytes memory pullData) internal virtual override returns (uint) {
    PullStruct memory offer = abi.decode(pullData, (PullStruct));
    address route = routes[offer.owner][token][offer.olKeyHash][offer.offerId];
    // return route.execPull(...)
  }

  function __push__(IERC20 token, uint amount, bytes memory pushData) internal virtual override returns (uint pushed) {}

  function __checkList__(IERC20 token, address reserveId) internal view virtual override {
    revert("DispatcherRouter/NotImplemented");
  }

  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    revert("DispatcherRouter/NotImplemented");
  }
}
