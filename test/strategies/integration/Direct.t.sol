// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {AbstractRouter, SmartRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {OfferLogicTest} from "./abstract/OfferLogic.t.sol";
import {IMangrove, IERC20, MangroveOffer} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {DirectTester, Direct, ITesterContract} from "@mgv-strats/test/lib/agents/DirectTester.sol";
import {MgvLib} from "@mgv/src/core/MgvLib.sol";
import {TestSender} from "@mgv/test/lib/agents/TestSender.sol";
import "@mgv/lib/Debug.sol";

contract DirectTest is OfferLogicTest {
  DirectTester direct;

  function setUp() public virtual override {
    vm.deal(deployer, 10 ether);
    super.setUp();
  }

  function setupMakerContract() internal virtual override {
    // deployer is the owner of the direct strat
    deployer = owner;
    vm.deal(deployer, 10 ether);

    vm.startPrank(deployer);
    AbstractRouter routerImplementation = AbstractRouter(address(new SmartRouter(address(0))));
    direct = new DirectTester({
      mgv: IMangrove($(mgv)),
      routerParams: Direct.RouterParams({routerImplementation: routerImplementation, fundOwner: owner, strict: false})
    });
    routerImplementation.bind(address(direct));
    direct.activate(weth);
    direct.activate(usdc);
    vm.stopPrank();
    gasreq = 160_000;
    vm.deal(owner, 10 ether);

    makerContract = ITesterContract(address(direct)); // to use for all non `IForwarder` specific tests.
    // owner approves direct's router to pull weth or usdc from his wallet
    vm.startPrank(owner);
    weth.approve(address(direct.router()), type(uint).max);
    usdc.approve(address(direct.router()), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  function test_updateOffer_with_funds_increases_owner_balance_on_mangrove() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
    uint old_provision = mgv.balanceOf(address(makerContract));

    vm.startPrank(owner);
    makerContract.updateOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      offerId: offerId,
      gasreq: gasreq
    });
    vm.stopPrank();
    uint new_provision = mgv.balanceOf(address(makerContract));
    assertEq(new_provision, old_provision + 0.1 ether, "Invalid provision");
  }

  function test_only_owner_can_post_offers() public {
    address new_maker = freshAddress("New maker");
    vm.deal(new_maker, 1 ether);
    vm.expectRevert("AccessControlled/Invalid");
    vm.startPrank(new_maker);
    makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
  }

  // Direct calls `flush` during `makerPosthook` this test makes it fail.
  function test_put_fail_reverts_with_expected_reason() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;

    deal(address(usdc), address(makerContract), 10 ** 6);

    vm.startPrank(deployer);
    makerContract.approve(usdc, address(direct.router()), 0);
    vm.stopPrank();

    order.olKey = olKey;
    order.takerGives = 10 ** 6;
    result.mgvData = "mgv/tradeSuccess";
    vm.expectRevert("router/flushFailed");
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }

  function makerExecute_succeeds_without_push_approval() public {
    MgvLib.SingleOrder memory order;
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    // simulating a taker taking the offer partially
    deal(address(usdc), address(makerContract), 10 ** 6);

    // Direct does not put during makerExecute so removing allowance should not matter
    vm.startPrank(deployer);
    makerContract.approve(usdc, address(direct.router()), 0);
    vm.stopPrank();

    order.olKey = olKey;
    order.takerGives = 10 ** 6;
    order.offerId = offerId;
    vm.prank($(mgv));
    makerContract.makerExecute(order);
  }
}
