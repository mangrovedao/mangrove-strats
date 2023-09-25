// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "mgv_src/IERC20.sol";
import {MonoRouter, AbstractRouter} from "./MonoRouter.sol";

///@title `MultiRouter` instances have token and reserveId dependant sourcing strategies.
abstract contract MultiRouter is AbstractRouter {
  ///@notice the specific router to use for a given token and reserveId.
  mapping(IERC20 token => mapping(address reserveId => MonoRouter)) public routes;

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 token, address reserveId) internal view override returns (uint) {
    return routes[token][reserveId].ROUTER_GASREQ();
  }

  ///@notice sets the router to use for a given token and reserve id.
  ///@param token the token to set the router for.
  ///@param reserveId the reserveId to set the router for.
  ///@param router the router to set.
  function setRoute(IERC20 token, address reserveId, MonoRouter router) external onlyBound {
    routes[token][reserveId] = router;
  }
}
