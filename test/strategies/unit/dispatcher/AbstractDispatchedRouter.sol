// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.18;

import {OfferLogicTest, IERC20, TestToken, TestSender} from "../OfferLogic.t.sol";
import {PolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "@mgv/test/lib/AllMethodIdentifiersTest.sol";
import {
  OfferDispatcherTester,
  ITesterContract as ITester,
  IMangrove
} from "@mgv-strats/src/toy_strategies/offer_forwarder/OfferDispatcherTester.sol";
import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/integrations/DispatcherRouter.sol";
import "@mgv/lib/Debug.sol";

abstract contract AbstractDispatchedRouter is OfferLogicTest {
  OfferDispatcherTester offerDispatcher;
  DispatcherRouter router;

  function setUp() public virtual override {
    deployer = freshAddress("deployer");
    vm.deal(deployer, 10 ether);
    super.setUp();
  }

  function setupMakerContract() internal virtual override {
    vm.prank(deployer);

    offerDispatcher = new OfferDispatcherTester({
      mgv: IMangrove($(mgv)),
      deployer: deployer
    });

    router = DispatcherRouter(address(offerDispatcher.router()));

    owner = payable(address(new TestSender()));
    vm.deal(owner, 10 ether);

    makerContract = ITester(address(offerDispatcher));

    vm.startPrank(owner);
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }
}
