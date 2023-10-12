// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.19;

import {AbstractDispatchedRouter, OfferLogicTest, IERC20, TestToken, console} from "./AbstractDispatchedRouter.sol";

import {PolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "@mgv/test/lib/AllMethodIdentifiersTest.sol";

import {
  StargateDispatchedRouter,
  AbstractRouter
} from "@mgv-strats/src/strategies/routers/integrations/dispatched/StargateDispatchedRouter.sol";
import {SimpleRouter} from "@mgv-strats/src/strategies/routers/SimpleRouter.sol";
import {Dispatcher} from "@mgv-strats/src/strategies/routers/integrations/Dispatcher.sol";

import {IStargateRouter} from "@mgv-strats/src/strategies/vendor/stargate/IStargateRouter.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/stargate/IPool.sol";

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

  function activate() public {}

  function fundStrat() internal virtual override {
    super.fundStrat();
    // 3000 USDC instead of 2000 to the owner (fees collected by the strategy)
    deal($(usdc), owner, cash(usdc, 3000));

    vm.startPrank(owner);
    // approve and supply weth to stargate
    usdc.approve(address(stargate), type(uint).max);
    stargate.addLiquidity(STARGATE_USDC_POOL_ID, cash(usdc, 3000), owner);
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

    offerDispatcher.activate(dynamic([IERC20(usdc)]), stargateRouter);
    offerDispatcher.activate(dynamic([IERC20(weth)]), simpleRouter);

    vm.stopPrank();

    IPool stargateUSDCLP = stargate.factory().getPool(STARGATE_USDC_POOL_ID);

    vm.startPrank(owner);
    stargateUSDCLP.approve(address(makerContract.router()), type(uint).max);

    offerDispatcher.setRoute(usdc, owner, stargateRouter);
    // weth is not available on stargate
    offerDispatcher.setRoute(weth, owner, simpleRouter);
    vm.stopPrank();
  }

  function performTrade(bool success)
    internal
    virtual
    override
    returns (uint takerGot, uint takerGave, uint bounty, uint fee)
  {
    vm.startPrank(owner);
    // ask 2000 USDC for 1 weth
    makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: 1_000_000
    });
    vm.stopPrank();

    // taker has approved mangrove in the setUp
    vm.startPrank(taker);
    (takerGot, takerGave, bounty, fee) =
      mgv.marketOrderByVolume({olKey: olKey, takerWants: 0.5 ether, takerGives: cash(usdc, 1000), fillWants: true});
    vm.stopPrank();
    assertTrue(!success || (bounty == 0 && takerGot > 0), "unexpected trade result");
  }
}
