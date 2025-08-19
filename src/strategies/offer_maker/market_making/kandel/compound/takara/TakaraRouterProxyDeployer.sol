// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TakaraRouter, ITakaraComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraRouter.sol";
import {TakaraRouterDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/takara/TakaraRouterDeployer.sol";
import {RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

contract TakaraRouterProxyDeployer is TakaraRouterDeployer {
  TakaraRouter public immutable ROUTER_IMPLEMENTATION;

  constructor(ITakaraComptroller _comptroller) TakaraRouterDeployer(_comptroller) {
    ROUTER_IMPLEMENTATION = new TakaraRouter(_comptroller);
  }

  function deployRouter() external override returns (AbstractRouter router) {
    router = AbstractRouter(address(new RouterProxy(ROUTER_IMPLEMENTATION)));
    router.setAdmin(msg.sender);
  }
}
