// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "mgv_src/IERC20.sol";
import {MonoRouter, AbstractRouter} from "./MonoRouter.sol";

///@title `MultiRouter` instances have reserveId dependant sourcing strategies.
abstract contract MultiRouter is AbstractRouter {
  mapping(IERC20 token => mapping(address reserveId => MonoRouter)) public routes;

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 token, address reserveId) internal view override returns (uint) {
    return routes[token][reserveId].ROUTER_GASREQ();
  }

  function setRoute(IERC20 token, address reserveId, MonoRouter router) external onlyBound {
    routes[token][reserveId] = router;
  }
}
