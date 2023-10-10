// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.20;

import {AbstractDispatchedRouter, OfferLogicTest, IERC20, TestToken, console} from "./AbstractDispatchedRouter.sol";

import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";

import {
  StargateDispatchedRouter,
  AbstractRouter
} from "mgv_strat_src/strategies/routers/integrations/dispatched/StargateDispatchedRouter.sol";
import {SimpleRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {Dispatcher} from "mgv_strat_src/strategies/routers/integrations/Dispatcher.sol";

import {IStargateRouter} from "mgv_strat_src/strategies/vendor/stargate/IStargateRouter.sol";
import {IPool} from "mgv_strat_src/strategies/vendor/stargate/IPool.sol";

contract StargateDispatchedRouterTest is AbstractDispatchedRouter {
  SimpleRouter internal simpleRouter;
  StargateDispatchedRouter internal stargateRouter;

  IStargateRouter internal stargate;

  uint16 internal constant STARGATE_USDC_POOL_ID = 1;

  function setUp() public virtual override {
    // deploying mangrove and opening WETH/USDC market.
    fork = new PolygonFork();
    super.setUp();
  }

  function fundStrat() internal virtual override {
    super.fundStrat();
    vm.startPrank(owner);
    // approve and supply weth to stargate
    usdc.approve(address(stargate), type(uint).max);
    stargate.addLiquidity(STARGATE_USDC_POOL_ID, cash(usdc, 2000), owner);
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal virtual override {
    stargate = IStargateRouter(fork.get("Stargate"));

    vm.startPrank(deployer);
    stargateRouter = new StargateDispatchedRouter({
      routerGasreq_: 1_000_000,
      _stargateRouter: stargate
    });

    simpleRouter = new SimpleRouter();
    vm.stopPrank();

    IPool stargateUSDCLP = stargate.factory().getPool(STARGATE_USDC_POOL_ID);

    vm.startPrank(owner);
    stargateUSDCLP.approve(address(makerContract.router()), type(uint).max);

    offerDispatcher.setRoute(usdc, owner, stargateRouter);
    // weth is not available on stargate
    offerDispatcher.setRoute(weth, owner, simpleRouter);
    vm.stopPrank();
  }
}