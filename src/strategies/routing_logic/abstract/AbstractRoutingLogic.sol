// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

abstract contract AbstractRoutingLogic {
  uint public immutable PULL_GAS_REQ;

  uint public immutable PUSH_GAS_REQ;

  constructor(uint pullGasReq_, uint pushGasReq_) {
    PULL_GAS_REQ = pullGasReq_;
    PUSH_GAS_REQ = pushGasReq_;
  }

  function executePullLogic(IERC20 token, uint amount, DispatcherRouter.PullStruct calldata pullData)
    external
    virtual
    returns (uint);

  function executePushLogic(IERC20 token, uint amount, DispatcherRouter.PushStruct calldata pushData)
    external
    virtual
    returns (uint);
}
