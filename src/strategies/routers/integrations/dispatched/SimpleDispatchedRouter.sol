// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MonoRouter, AbstractRouter} from "../../abstract/MonoRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer} from "../AaveMemoizer.sol";
import {ReserveConfiguration, DataTypes} from "../../abstract/AbstractAaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

// TODO: check gas requirements

/// @title `SimpleDispatchedRouter` is a dispatched router that simply uses an address as reserve
contract SimpleDispatchedRouter is MonoRouter(30_000) {
  /// @dev Transfers token from the user to the maker contract
  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool) internal virtual override returns (uint) {
    require(TransferLib.transferTokenFrom(token, reserveId, msg.sender, amount), "SimpleDispatchedRouter/pullFailed");
    return amount;
  }

  /// @dev Transfers token from the maker contract to the user
  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, reserveId, amount), "SimpleDispatchedRouter/pushFailed");
    return amount;
  }

  /// @dev Checks that user has approved the router to spend its tokens
  /// @inheritdoc	AbstractRouter
  function __checkList__(IERC20 token, address reserveId) internal view virtual override {
    require(token.allowance(reserveId, address(this)) > 0, "SimpleDispatchedRouter/NotApproved");
  }

  /// @inheritdoc	AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    return token.balanceOf(reserveId);
  }
}
