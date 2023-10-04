// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferLogicTest} from "./OfferLogic.t.sol";
import {AbstractRouter, SimpleRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";

contract AbstractRouterTest is OfferLogicTest {
  AbstractRouter internal router;

  event MakerBind(address indexed maker);
  event MakerUnbind(address indexed maker);

  function setupLiquidityRouting() internal virtual override {
    // OfferMaker has no router, replacing 0x router by a SimpleRouter
    vm.prank(deployer);
    router = new SimpleRouter();
    expectFrom(address(router));
    emit MakerBind(address(makerContract));
    vm.prank(deployer);
    router.bind(address(makerContract));
    // maker must approve router
    vm.prank(deployer);
    makerContract.setRouter(router);

    vm.startPrank(owner);
    weth.approve(address(router), type(uint).max);
    usdc.approve(address(router), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  function test_isBound() public {
    assertTrue(router.isBound(address(makerContract)), "Maker contract should be bound to router");
    assertTrue(!router.isBound(deployer), "Admin should not be bound");
  }

  function test_admin_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    vm.prank(deployer);
    router.unbind(address(makerContract));
  }

  function test_maker_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    vm.prank(address(makerContract));
    router.unbind();
  }

  function test_only_makerContract_can_push() public {
    // so that push does not supply to the pool
    deal($(usdc), address(this), 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    router.push(usdc, address(this), 10 ** 6);

    deal($(usdc), deployer, 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(deployer);
    router.push(usdc, deployer, 10 ** 6);

    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    router.push(usdc, address(makerContract), 10 ** 6);
  }

  // this takes assumes pull can be done from router's balance
  // override this test if this is not true
  function test_only_makerContract_can_pull() public virtual {
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    router.push(usdc, address(makerContract), 10 ** 6);

    vm.expectRevert("AccessControlled/Invalid");
    router.pull(usdc, address(this), 10 ** 6, true);

    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(deployer);
    router.pull(usdc, deployer, 10 ** 6, true);

    vm.prank(address(makerContract));
    router.pull(usdc, address(makerContract), 10 ** 6, true);
  }
}
