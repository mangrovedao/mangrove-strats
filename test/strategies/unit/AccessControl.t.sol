// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";

import {DirectTester} from "@mgv-strats/src/toy_strategies/offer_maker/DirectTester.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

contract AccessControlTest is StratTest {
  TestToken weth;
  TestToken usdc;
  address payable admin;
  DirectTester makerContract;

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    admin = freshAddress("admin");
    deal(admin, 1 ether);

    DirectTester.RouterParams memory noRouter;
    vm.prank(admin);
    makerContract = new DirectTester({
      mgv: IMangrove($(mgv)),
      routerParams: noRouter
    });

    vm.startPrank(admin);
    weth.approve(address(makerContract), type(uint).max);
    usdc.approve(address(makerContract), type(uint).max);
    vm.stopPrank();
  }

  function testCannot_setAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setAdmin(freshAddress());
  }

  function test_admin_can_set_admin() public {
    address newAdmin = freshAddress("newAdmin");
    vm.prank(admin);
    makerContract.setAdmin(newAdmin);
    assertEq(makerContract.admin(), newAdmin, "Incorrect admin");
  }
}
