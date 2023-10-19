// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {IERC4626} from "@mgv-strats/src/strategies/vendor/IERC4626.sol";

contract ERC4626Logic is AbstractRoutingLogic {
  IERC4626 public immutable ERC4626;

  constructor(IERC4626 erc4626, uint pullGasReq_, uint pushGasReq_) AbstractRoutingLogic(pullGasReq_, pushGasReq_) {
    ERC4626 = erc4626;
  }

  function executePullLogic(IERC20 token, uint amount, DispatcherRouter.PullStruct calldata pullData)
    external
    virtual
    override
    returns (uint)
  {
    uint _amountToWithdraw = ERC4626.convertToShares(amount);
    DispatcherRouter(msg.sender).executeTransfer(token, ERC4626, _amountToWithdraw, pullData);
    ERC4626.withdraw(amount, pullData.caller, address(this));
  }

  function executePushLogic(IERC20, uint amount, DispatcherRouter.PushStruct calldata pushData)
    external
    virtual
    override
    returns (uint)
  {
    ERC4626.deposit(amount, pushData.owner);
    return amount;
  }
}
