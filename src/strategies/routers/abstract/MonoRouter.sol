// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {AbstractRouter} from "./AbstractRouter.sol";

///@title `MonoRouter` instances have a sourcing strategy which is reserveId and caller independent.
///@dev `routerGasreq(address reserveId)` is thus a constant function.
abstract contract MonoRouter is AbstractRouter {
  uint public immutable ROUTER_GASREQ;

  constructor(uint routerGasreq_) {
    ROUTER_GASREQ = routerGasreq_;
  }

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20, address) internal view override returns (uint) {
    return ROUTER_GASREQ;
  }
}
