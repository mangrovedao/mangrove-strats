// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TakaraRouter, ITakaraComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraRouter.sol";
import {CompoundRouterDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundRouterDeployer.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

contract TakaraRouterDeployer is CompoundRouterDeployer {
  ITakaraComptroller public immutable comptroller;

  constructor(ITakaraComptroller _comptroller) {
    comptroller = _comptroller;
  }

  function deployRouter() external virtual override returns (AbstractRouter router) {
    router = new TakaraRouter(comptroller);
    router.setAdmin(msg.sender);
  }
}
