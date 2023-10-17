// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title AbstractRoutingLogic
/// @notice Abstract contract for routing logic
abstract contract AbstractRoutingLogic {
  /// @notice Gas requirements for `pull` logic execution regardless of the token
  uint public immutable PULL_GAS_REQ;

  /// @notice Gas requirements for `push` logic execution regardless of the token
  uint public immutable PUSH_GAS_REQ;

  /// @notice Constructor
  /// @param pullGasReq_ gas requirements for `pull` logic execution regardless of the token
  /// @param pushGasReq_ gas requirements for `push` logic execution regardless of the token
  constructor(uint pullGasReq_, uint pushGasReq_) {
    PULL_GAS_REQ = pullGasReq_;
    PUSH_GAS_REQ = pushGasReq_;
  }

  /// @notice Executes the pull logic
  /// @dev This function may only be called by a `DispatcherRouter` instance
  /// * Otherwise, it will fail
  /// @param token The token to pull
  /// @param amount The amount to pull
  /// @param pullData The pull data from the `DispatcherRouter` `pull` request
  /// @return pulled The amount of tokens pulled
  function executePullLogic(IERC20 token, uint amount, DispatcherRouter.PullStruct calldata pullData)
    external
    virtual
    returns (uint);

  /// @notice Executes the push logic
  /// @dev Thsi function will be called by a `DispatcherRouter` instance
  /// * the `amount` of `token` will already have been transferred to this contract before call
  /// @param token The token to push
  /// @param amount The amount to push
  /// @param pushData The push data from the `DispatcherRouter` `push` request
  function executePushLogic(IERC20 token, uint amount, DispatcherRouter.PushStruct calldata pushData)
    external
    virtual
    returns (uint);
}
