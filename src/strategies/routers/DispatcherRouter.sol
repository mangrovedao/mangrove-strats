// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {MonoRouter, AbstractRouter} from "./abstract/MonoRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

///@title `MultiRouter` instances may have token and reserveId dependant sourcing strategies.
contract DispatcherRouter is AbstractRouter {
  ///@notice logs new routes and route updates.
  ///@dev TODO: set router to type of strategy.
  event SetRoute(
    address indexed owner, IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRoutingLogic logic
  );

  ///@notice the specific route to use
  mapping(
    address owner
      => mapping(IERC20 token => mapping(bytes32 olKeyHash => mapping(uint offerId => AbstractRoutingLogic logic)))
  ) public routes;

  struct PullStruct {
    address owner;
    address caller;
    bytes32 olKeyHash;
    uint offerId;
  }

  struct PushStruct {
    address owner;
    bytes32 olKeyHash;
    uint offerId;
  }

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 token, address reserveId) internal view override returns (uint) {
    revert("DispatcherRouter/NotImplemented");
  }

  ///@notice This function is used to set the routing strategy for a given offer.
  ///@param token the token that the offer is for.
  ///@param olKeyHash the olKeyHash that the offer is for.
  ///@param offerId the offerId that the offer is for.
  ///@param logic the loggic to use for the given offer.
  function setRoute(IERC20 token, bytes32 olKeyHash, uint offerId, AbstractRoutingLogic logic) external {
    routes[msg.sender][token][olKeyHash][offerId] = logic;
    emit SetRoute(msg.sender, token, olKeyHash, offerId, logic);
  }

  /// @notice Exectue a transfer for the wanted supposed overlying from the owner to the caller
  /// @dev This assumes that the user has given allowance of the supoosed overlying to this contract
  /// * This function is called by the routing logic contract
  /// @param underlying The underlying token
  /// @param overlying The overlying token (token we want to pull)
  /// @param amount The amount of overlying to pull
  /// @param offer The pull data from the `DispatcherRouter` `pull` request
  /// @return success True if the transfer was successful
  function executeTransfer(IERC20 underlying, IERC20 overlying, uint amount, PullStruct calldata offer)
    external
    returns (bool)
  {
    AbstractRoutingLogic route = routes[offer.owner][underlying][offer.olKeyHash][offer.offerId];
    require(address(route) == msg.sender, "DispatcherRouter/InvalidAccess");
    return TransferLib.transferTokenFrom(overlying, offer.owner, msg.sender, amount);
  }

  /// @notice Pulls the funds from the owner wallet
  /// @param token The token to pull
  /// @param amount The amount to pull
  /// @param offer The pull data from the `DispatcherRouter` `pull` request
  /// @return pulled The amount of tokens pulled
  function simplePull(IERC20 token, uint amount, PullStruct memory offer) internal returns (uint) {
    require(TransferLib.transferTokenFrom(token, offer.owner, msg.sender, amount), "DispatcherRouter/TransferFailed");
    return amount;
  }

  /// @inheritdoc AbstractRouter
  /// @dev pulls liquidity regarding the logic selected by the offer.
  function __pull__(IERC20 token, uint amount, bytes memory pullData) internal virtual override returns (uint) {
    PullStruct memory offer = abi.decode(pullData, (PullStruct));
    AbstractRoutingLogic route = routes[offer.owner][token][offer.olKeyHash][offer.offerId];
    if (address(route) == address(0)) {
      return simplePull(token, amount, offer);
    }
    return route.executePullLogic(token, amount, offer);
  }

  /// @notice Pushes the funds to the owner wallet
  /// @param token The token to push
  /// @param amount The amount to push
  /// @param offer The push data from the `DispatcherRouter` `push` request
  /// @return pushed The amount of tokens pushed
  function simplePush(IERC20 token, uint amount, PushStruct memory offer) internal returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, offer.owner, amount), "DispatcherRouter/TransferFailed");
    return amount;
  }

  /// @inheritdoc AbstractRouter
  /// @dev sends liquidity to the logic contract selected by the offer.
  /// * Then it executes the push logic from the logic contract.
  function __push__(IERC20 token, uint amount, bytes memory pushData) internal virtual override returns (uint pushed) {
    PushStruct memory offer = abi.decode(pushData, (PushStruct));
    AbstractRoutingLogic route = routes[offer.owner][token][offer.olKeyHash][offer.offerId];
    if (address(route) == address(0)) {
      return simplePush(token, amount, offer);
    }
    require(TransferLib.transferTokenFrom(token, msg.sender, address(route), amount), "DispatcherRouter/TransferFailed");
    return route.executePushLogic(token, amount, offer);
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId) internal view virtual override {
    revert("DispatcherRouter/NotImplemented");
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    revert("DispatcherRouter/NotImplemented");
  }
}
