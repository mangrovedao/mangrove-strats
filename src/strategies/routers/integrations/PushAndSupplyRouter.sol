// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AbstractRouter} from "../AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration} from "./AaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

abstract contract PushAndSupplyRouter is AbstractRouter {
  ///@notice contract's constructor
  ///@param overhead is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  ///@dev `msg.sender` will be admin of this router
  constructor(uint overhead) AbstractRouter(overhead) {}

  function pushAndSupply(IERC20 token0, uint amount0, IERC20 token1, uint amount1, address reserveId)
    external
    virtual
    returns (uint pushed0, uint pushed1);
}
