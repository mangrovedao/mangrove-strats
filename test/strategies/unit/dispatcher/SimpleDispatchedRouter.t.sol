// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.18;

import {AbstractDispatchedRouter} from "./AbstractDispatchedRouter.sol";
import {SimpleRouter, AbstractRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";

contract SimpleDispatchedRouter is AbstractDispatchedRouter {
  SimpleRouter internal simpleRouter;

  function setupLiquidityRouting() internal virtual override {
    vm.prank(deployer);
    simpleRouter = new SimpleRouter();

    vm.startPrank(owner);
    offerDispatcher.setRoute(weth, owner, simpleRouter);
    offerDispatcher.setRoute(usdc, owner, simpleRouter);
    vm.stopPrank();
  }

  function test_keep_funds_after_new_offer() public {
    uint startWethBalance = makerContract.tokenBalance(weth, owner);

    vm.startPrank(owner);
    // ask 2000 USDC for 1 weth
    makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: makerContract.offerGasreq(weth, owner)
    });

    vm.stopPrank();

    uint endWethBalance = makerContract.tokenBalance(weth, owner);
    assertEq(endWethBalance, startWethBalance, "unexpected movement");
  }
}
