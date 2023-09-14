// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {MonoRouter, AbstractRouter} from "./MonoRouter.sol";

///@title `MultiRouter` instances have reserveId dependant sourcing strategies.
abstract contract MultiRouter is AbstractRouter {
  mapping(address => MonoRouter) public routes;

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(address reserveId) internal view override returns (uint) {
    return routes[reserveId].routerGasreq();
  }

  function setRoute(address reserveId, MonoRouter router) external onlyBound {
    routes[reserveId] = router;
  }
}
