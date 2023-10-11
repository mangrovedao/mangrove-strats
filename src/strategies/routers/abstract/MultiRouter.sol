// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "mgv_lib/IERC20.sol";
import {MonoRouter, AbstractRouter, ApprovalInfo} from "./MonoRouter.sol";

///@title `MultiRouter` instances may have token and reserveId dependant sourcing strategies.
abstract contract MultiRouter is AbstractRouter {
  ///@notice logs new routes and route updates.
  ///@param token the asset that will be routed via this strategy
  ///@param reserveId the reserve for which the asset is routed
  ///@param router the router.
  event SetRoute(IERC20 indexed token, address indexed reserveId, MonoRouter indexed router);

  ///@notice the specific router to use for a given token and reserveId.
  mapping(IERC20 token => mapping(address reserveId => MonoRouter)) public routes;

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 outbound_tkn, IERC20 inbound_tkn, address reserveId)
    internal
    view
    override
    returns (uint)
  {
    return __routerPushGasreq__(inbound_tkn, reserveId) + __routerPullGasreq__(outbound_tkn, inbound_tkn, reserveId);
  }

  ///@inheritdoc AbstractRouter
  function __routerPushGasreq__(IERC20 inbound_tkn, address reserveId) internal view override returns (uint) {
    return routes[inbound_tkn][reserveId].ROUTER_PUSH_GASREQ();
  }

  ///@inheritdoc AbstractRouter
  function __routerPullGasreq__(IERC20 outbound_tkn, IERC20, address reserveId) internal view override returns (uint) {
    return routes[outbound_tkn][reserveId].ROUTER_PULL_GASREQ();
  }

  ///@notice associates a router to a specific strategy for sourcing liquidity
  ///@param token the asset that will be routed via this strategy
  ///@param reserveId the reserve for which the asset is routed
  ///@param router the router to set.
  function setRoute(IERC20 token, address reserveId, MonoRouter router) external onlyBound {
    routes[token][reserveId] = router;
    emit SetRoute(token, reserveId, router);
  }
}
