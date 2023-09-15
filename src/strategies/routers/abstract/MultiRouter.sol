// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {MonoRouter, AbstractRouter} from "./MonoRouter.sol";

///@title `MultiRouter` instances have reserveId dependant sourcing strategies.
abstract contract MultiRouter is AbstractRouter {
  mapping(IERC20 token => mapping(address reserveId => MonoRouter)) public routes;

  ///@inheritdoc AbstractRouter
  function __routerGasreq__(IERC20 token, address reserveId) internal view override returns (uint) {
    return routes[token][reserveId].routerGasreq();
  }

  function setRoute(IERC20 token, address reserveId, MonoRouter router) external onlyBound {
    routes[token][reserveId] = router;
  }
}
