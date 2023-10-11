// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_lib/IERC20.sol";
import {AbstractRouter, ApprovalInfo} from "./AbstractRouter.sol";

///@title `MonoRouter` instances have a sourcing strategy which is reserveId and caller independent.
///@dev `routerGasreq(address reserveId)` is thus a constant function.
abstract contract MonoRouter is AbstractRouter {
  ///@notice the router specific gas requirement
  uint public immutable ROUTER_GASREQ;

  ///@notice the router push gas requirement
  uint public immutable ROUTER_PUSH_GASREQ;

  ///@notice the router pull gas requirement
  uint public immutable ROUTER_PULL_GASREQ;

  ///@notice Constructor
  ///@param routerGasreq_ the router specific gas requirement
  ///@param routerPushGasreq_ the router push gas requirement
  ///@param routerPullGasreq_ the router pull gas requirement
  constructor(uint routerGasreq_, uint routerPushGasreq_, uint routerPullGasreq_) {
    ROUTER_GASREQ = routerGasreq_;
    ROUTER_PUSH_GASREQ = routerPushGasreq_;
    ROUTER_PULL_GASREQ = routerPullGasreq_;
  }

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20, IERC20, address) internal view override returns (uint) {
    return ROUTER_GASREQ;
  }

  ///@inheritdoc AbstractRouter
  function __routerPushGasreq__(IERC20, address) internal view override returns (uint) {
    return ROUTER_PUSH_GASREQ;
  }

  ///@inheritdoc AbstractRouter
  function __routerPullGasreq__(IERC20, IERC20, address) internal view override returns (uint) {
    return ROUTER_PULL_GASREQ;
  }
}
