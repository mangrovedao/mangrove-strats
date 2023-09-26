// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.18;

import {OfferLogicTest, IERC20, TestToken, console, TestSender} from "../OfferLogic.t.sol";
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";
import {
  OfferDispatcherTester,
  ITesterContract as ITester,
  IMangrove
} from "mgv_strat_src/strategies/offer_forwarder/OfferDispatcherTester.sol";
import {Dispatcher} from "mgv_strat_src/strategies/routers/integrations/Dispatcher.sol";
import {SimpleRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";

contract OfferDispatcherTest is OfferLogicTest {
  OfferDispatcherTester offerDispatcher;
  SimpleRouter router;

  function setUp() public virtual override {
    deployer = freshAddress("deployer");
    vm.deal(deployer, 10 ether);
    super.setUp();
  }

  function setupMakerContract() internal virtual override {
    vm.prank(deployer);
    router = new SimpleRouter();

    offerDispatcher = new OfferDispatcherTester({
      mgv: IMangrove($(mgv)),
      deployer: deployer
    });

    owner = payable(address(new TestSender()));
    vm.deal(owner, 10 ether);

    makerContract = ITester(address(offerDispatcher));

    vm.startPrank(owner);
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal virtual override {
    vm.startPrank(owner);
    offerDispatcher.setRoute(weth, owner, router);
    offerDispatcher.setRoute(usdc, owner, router);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }
}
