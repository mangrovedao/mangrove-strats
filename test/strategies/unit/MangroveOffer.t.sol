// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv-strats/test/lib/StratTest.sol";
import {DirectTester} from "@mgv-strats/src/toy_strategies/offer_maker/DirectTester.sol";
import {SimpleRouter, AbstractRouter} from "@mgv-strats/src/strategies/routers/SimpleRouter.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";

contract MangroveOfferTest is StratTest {
  TestToken weth;
  TestToken usdc;
  address payable deployer;
  DirectTester makerContract;
  uint constant GASREQ = 50_000;

  // tracking IOfferLogic logs
  event LogIncident(bytes32 indexed olKeyHash, uint indexed offerId, bytes32 makerData, bytes32 mgvData);

  event SetAdmin(address);
  event SetRouter(address);

  function setUp() public override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    // populates `weth`,`usdc` and `mgv`
    // opens WETH/USDC market on mangrove

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    deployer = payable(new TestSender());
    vm.prank(deployer);
    makerContract = new DirectTester({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)), // no router
      deployer: deployer
    });
  }

  function test_Admin_is_deployer() public {
    assertEq(makerContract.admin(), deployer, "Incorrect admin");
  }

  function testCannot_activate_if_not_admin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  function test_a_checkList_with_router() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    makerContract.checkList(tokens);
  }

  function test_b_checkList_router_not_bound() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("Router/callerIsNotBoundToRouter");
    makerContract.checkList(tokens);
  }

  function test_c_checkList_router_not_approved() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("Router/NotApprovedByMakerContract");
    makerContract.checkList(tokens);
  }

  function test_d_checkList_router_not_approved_by_reserve() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    // passes c
    makerContract.approve(weth, address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("SimpleRouter/NotApprovedByOwner");
    makerContract.checkList(tokens);
  }

  function test_e_checkList_completes() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    // passes c
    makerContract.approve(weth, address(makerContract.router()), type(uint).max);
    // passes d
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    makerContract.checkList(tokens);
    // ^^ should not throw
  }

  function test_activate_completes_checkList_for_deployer() public {
    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    // reserve approves router for weth transfer
    address toApprove =
      makerContract.router() == makerContract.NO_ROUTER() ? address(makerContract) : address(makerContract.router());

    vm.startPrank(deployer);
    weth.approve(toApprove, type(uint).max);
    usdc.approve(toApprove, type(uint).max);

    makerContract.activate(tokens);
    makerContract.checkList(tokens);
    vm.stopPrank();
  }

  function test_activate_throws_if_approve_mangrove_fails() public {
    // asks weth contract to return false to approve and transfer calls
    weth.failSoftly(true);
    vm.expectRevert("mgvOffer/approveMangrove/Fail");
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(weth)]));
  }

  // makerExecute and makerPosthook guards
  function testCannot_call_makerExecute_if_not_Mangrove() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerExecute(order);
    vm.prank(address(mgv));
    bytes32 ret = makerContract.makerExecute(order);
    assertEq(ret, "lastLook/testData", "Incorrect returned data");
  }

  function testCannot_call_makerPosthook_if_not_Mangrove() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerPosthook(order, result);
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_failed_trade_is_logged() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    result.mgvData = "anythingButSuccess";
    result.makerData = "failReason";

    vm.expectEmit(true, false, false, true);
    emit LogIncident(order.olKey.hash(), 0, result.makerData, result.mgvData);
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_failed_to_repost_is_logged() public {
    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockPartialFillBuyOrder({
      takerWants: 1 ether,
      tick: TickLib.tickFromVolumes(1500 * 10 ** 6, 1 ether),
      partialFill: 2, // half of offer is consumed
      _olBaseQuote: olKey,
      makerData: "whatever"
    });
    expectFrom(address(makerContract));
    emit LogIncident(olKey.hash(), 0, "whatever", "mgv/updateOffer/unauthorized");
    vm.expectRevert("posthook/failed");
    /// since order.offerId is 0, updateOffer will revert. This revert should be caught and logged
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_lastLook_returned_value_is_passed() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    vm.prank(address(mgv));
    bytes32 data = makerContract.makerExecute(order);
    assertEq(data, "lastLook/testData");
  }

  function test_admin_can_withdrawFromMangrove() public {
    assertEq(mgv.balanceOf(address(makerContract)), 0, "incorrect balance");
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawFromMangrove(0.5 ether, deployer);
    uint balMaker = deployer.balance;
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(0.5 ether, deployer);
    assertEq(mgv.balanceOf(address(makerContract)), 0.5 ether, "incorrect balance");
    assertEq(deployer.balance, balMaker + 0.5 ether, "incorrect balance");
  }

  function test_admin_can_WithdrawAllFromMangrove() public {
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(type(uint).max, deployer);
    assertEq(mgv.balanceOf(address(makerContract)), 0 ether, "incorrect balance");
    assertEq(deployer.balance, 1 ether, "incorrect balance");
  }

  function test_get_fail_reverts() public {
    MgvLib.SingleOrder memory order;
    deal($(usdc), $(this), 0);
    order.olKey = olKey;
    order.takerWants = 10 ** 6;
    vm.expectRevert("mgvOffer/abort/getFailed");
    vm.prank($(mgv));
    makerContract.makerExecute(order);
  }

  function test_withdrawFromMangrove_reverts_with_good_reason_if_caller_cannot_receive() public {
    TestSender(deployer).refuseNative();
    mgv.fund{value: 0.1 ether}(address(makerContract));
    vm.expectRevert("mgvOffer/weiTransferFail");
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(0.1 ether, $(this));
  }

  function test_setRouter_logs_SetRouter() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetRouter(address(0));
    vm.startPrank(deployer);
    makerContract.setRouter(AbstractRouter(address(0)));
  }

  function test_setAdmin_logs_SetAdmin() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetAdmin(deployer);
    vm.startPrank(deployer);
    makerContract.setAdmin(deployer);
  }

  function test_approves_token() public {
    vm.prank(deployer);
    makerContract.approve(weth, address(this), 42);
    assertEq(weth.allowance({spender: address(this), owner: address(makerContract)}), 42, "Incorrect allowance");
  }

  function test_approves_reverts_when_erc20_approve_fails() public {
    vm.mockCall($(weth), abi.encodeWithSelector(weth.approve.selector), abi.encode(false));
    vm.expectRevert("mgvOffer/approve/failed");
    vm.prank(deployer);
    makerContract.approve(weth, address(this), 42);
  }
}
