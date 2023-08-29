// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferLogicTest, IERC20, TestToken, console} from "./OfferLogic.t.sol";
import {AavePrivateRouter} from "mgv_strat_src/strategies/routers/integrations/AavePrivateRouter.sol";
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";
import {PoolAddressProviderMock} from "mgv_strat_script/toy/AaveMock.sol";

contract AavePrivateRouterTest is OfferLogicTest {
  bool internal useForkAave = true;

  AavePrivateRouter internal privateRouter;

  uint internal constant GASREQ = 1_000_000;

  event SetAaveManager(address);
  event AaveIncident(IERC20 indexed token, address indexed maker, address indexed reserveId, bytes32 aaveReason);

  IERC20 internal dai;

  uint internal bufferSize;
  uint internal interestRate = 2; // stable borrowing not enabled on polygon

  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PolygonFork();
    }
    super.setUp();

    vm.prank(deployer);
    makerContract.activate(dynamic([dai]));

    vm.startPrank(deployer);
    dai.approve({spender: $(privateRouter), amount: type(uint).max});
    weth.approve({spender: $(privateRouter), amount: type(uint).max});
    usdc.approve({spender: $(privateRouter), amount: type(uint).max});
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal override {
    dai = useForkAave ? dai = TestToken(fork.get("DAI")) : new TestToken($(this),"Dai","Dai",options.base.decimals);
    address aave = useForkAave
      ? fork.get("Aave")
      : address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])));

    vm.startPrank(deployer);
    AavePrivateRouter router = new AavePrivateRouter({
      addressesProvider:aave, 
      interestRate:interestRate, 
      overhead: GASREQ,
      buffer_size: bufferSize
    });
    router.bind(address(makerContract));
    makerContract.setRouter(router);
    vm.stopPrank();
    // although reserve is set to deployer the source remains makerContract since privateRouter is always the source of funds
    // having reserve pointing to deployed allows deployer to have multiple strats with the same shares on the router
    owner = deployer;
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE

    uint collateralAmount = 1_000_000 * 10 ** 18;

    privateRouter = AavePrivateRouter(address(makerContract.router()));

    deal($(dai), address(makerContract), collateralAmount);
    // router has only been activated for base and quote but is agnostic wrt collateral
    // here we want to use DAI (neither base or quote) as collateral so we need to activate the router to transfer it from the maker contract
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(dai)]));

    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(dai, collateralAmount, IERC20(address(0)), 0);
    assertEq(privateRouter.balanceOfReserve(dai, owner), collateralAmount, "Incorrect collateral balance");
  }

  // this test overrides the one in OfferLogic.t.sol with borrow specific strat balances
  function test_owner_balance_is_updated_when_trade_succeeds() public override {
    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");
    AavePrivateRouter.AssetBalances memory balUsdc = privateRouter.assetBalances(usdc);

    // all incoming USDCs should be on the router (DirectTester does not ask for depositing on AAVE)
    assertEq(balUsdc.onPool, 0, "There should be no USDC balance on pool");
    assertEq(balUsdc.local, takergave, "Incorrect USDC on the router");
    assertEq(balUsdc.debt, 0, "There should be no USDC debt");

    AavePrivateRouter.AssetBalances memory balWeth = privateRouter.assetBalances(weth);
    assertEq(balWeth.debt, takergot + fee, "Incorrect WETH debt");
    assertEq(balWeth.local, 0, "There should be no WETH on the router");
    assertEq(balWeth.onPool, 0, "There should be no WETH on the pool");
  }

  // function test_only_makerContract_can_push() public {
  //   // so that push does not supply to the pool
  //   deal($(usdc), address(this), 10 ** 6);
  //   vm.expectRevert("AccessControlled/Invalid");
  //   privateRouter.push(usdc, address(this), 10 ** 6);

  //   deal($(usdc), deployer, 10 ** 6);
  //   vm.expectRevert("AccessControlled/Invalid");
  //   vm.prank(deployer);
  //   privateRouter.push(usdc, deployer, 10 ** 6);
  // }

  // function test_supply_error_is_logged() public {
  //   TestToken pixieDust = new TestToken({
  //     admin: address(this),
  //     name: "Pixie Dust",
  //     symbol: "PXD",
  //     _decimals: uint8(18)
  //   });

  //   deal($(pixieDust), address(makerContract), 1 ether);
  //   vm.prank(address(makerContract));
  //   pixieDust.approve($(privateRouter), type(uint).max);
  //   vm.prank(deployer);
  //   privateRouter.activate(pixieDust);

  //   expectFrom($(privateRouter));
  //   emit AaveIncident({token: pixieDust, maker: address(makerContract), reserveId: owner, aaveReason: "noReason"});
  //   vm.prank(address(makerContract));
  //   privateRouter.pushAndSupply(pixieDust, 1 ether, pixieDust, 0, owner);
  //   // although aave refused the deposit, funds should be on the router
  //   assertEq(privateRouter.balanceOfReserve(pixieDust, owner), 1 ether, "Incorrect balance on router");
  // }

  // function test_initial_aave_manager_is_deployer() public {
  //   assertEq(privateRouter.aaveManager(), deployer, "unexpected rewards manager");
  // }

  // function test_admin_can_set_new_aave_manager() public {
  //   vm.expectRevert("AccessControlled/Invalid");
  //   privateRouter.setAaveManager($(this));

  //   expectFrom($(privateRouter));
  //   emit SetAaveManager($(this));
  //   vm.prank(deployer);
  //   privateRouter.setAaveManager($(this));
  //   assertEq(privateRouter.aaveManager(), $(this), "unexpected rewards manager");
  // }

  // function test_aave_manager_can_revoke_aave_approval() public {
  //   assertTrue(
  //     weth.allowance({spender: address(privateRouter.POOL()), owner: $(privateRouter)}) > 0,
  //     "Allowance should be positive"
  //   );
  //   vm.prank(deployer);
  //   privateRouter.setAaveManager($(this));
  //   privateRouter.revokeLenderApproval(weth);
  //   assertEq(
  //     weth.allowance({spender: address(privateRouter.POOL()), owner: $(privateRouter)}), 0, "Allowance should be 0"
  //   );
  // }

  // event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  // event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  // function test_aave_manager_can_exit_market() public {
  //   // pooled router has entered weth and usdc market when first supplying
  //   vm.prank(deployer);
  //   privateRouter.setAaveManager($(this));
  //   expectFrom(address(privateRouter.POOL()));
  //   emit ReserveUsedAsCollateralDisabled($(weth), $(privateRouter));
  //   privateRouter.exitMarket(weth);
  // }

  // function test_aave_manager_can_reenter_market() public {
  //   // pooled router has entered weth and usdc market when first supplying
  //   vm.prank(deployer);
  //   privateRouter.setAaveManager($(this));
  //   privateRouter.exitMarket(weth);

  //   expectFrom(address(privateRouter.POOL()));
  //   emit ReserveUsedAsCollateralEnabled($(weth), $(privateRouter));
  //   privateRouter.enterMarket(dynamic([IERC20(weth)]));
  // }

  // function test_deposit_on_aave_maintains_reserve_and_total_balance() public {
  //   deal($(usdc), address(makerContract), 10 ** 6);
  //   vm.prank(address(makerContract));
  //   privateRouter.push(usdc, address(makerContract), 10 ** 6);

  //   uint reserveBalance = privateRouter.balanceOfReserve(usdc, address(makerContract));
  //   uint totalBalance = privateRouter.totalBalance(usdc);

  //   vm.prank(deployer);
  //   privateRouter.flushBuffer(usdc, false);

  //   assertApproxEqAbs(
  //     reserveBalance, privateRouter.balanceOfReserve(usdc, address(makerContract)), 1, "Incorrect reserve balance"
  //   );
  //   assertApproxEqAbs(totalBalance, privateRouter.totalBalance(usdc), 1, "Incorrect total balance");
  // }

  // function test_makerContract_has_initially_zero_shares() public {
  //   assertEq(privateRouter.sharesOf(dai, address(makerContract)), 0, "Incorrect initial shares");
  // }

  // function test_push_token_increases_user_shares() public {
  //   deal($(dai), maker1, 1 * 10 ** 18);
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 1 * 10 ** 18);
  //   deal($(dai), maker2, 2 * 10 ** 18);
  //   vm.prank(maker2);
  //   privateRouter.push(dai, maker2, 2 * 10 ** 18);

  //   assertEq(privateRouter.sharesOf(dai, maker2), 2 * privateRouter.sharesOf(dai, maker1), "Incorrect shares");
  // }

  // function test_pull_token_decreases_user_shares() public {
  //   deal($(dai), maker1, 1 * 10 ** 18);
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 1 * 10 ** 18);
  //   deal($(dai), maker2, 2 * 10 ** 18);
  //   vm.prank(maker2);
  //   privateRouter.push(dai, maker2, 2 * 10 ** 18);

  //   vm.prank(maker1);
  //   privateRouter.pull(dai, maker1, 1 * 10 ** 18, true);

  //   assertEq(privateRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  // }

  // function test_mockup_marketOrder_gas_cost() public {
  //   deal($(dai), maker1, 10 ** 18);

  //   vm.startPrank(maker1);
  //   uint gas = gasleft();
  //   privateRouter.push(dai, maker1, 10 ** 18);
  //   vm.stopPrank();

  //   uint shallow_push_cost = gas - gasleft();

  //   vm.prank(deployer);
  //   privateRouter.flushBuffer(dai, false);

  //   vm.startPrank(maker1);
  //   gas = gasleft();
  //   /// this emulates a `get` from the offer logic
  //   privateRouter.pull(dai, maker1, 0.5 ether, false);
  //   vm.stopPrank();

  //   uint deep_pull_cost = gas - gasleft();

  //   deal($(usdc), maker1, 10 ** 6);

  //   vm.startPrank(maker1);
  //   gas = gasleft();
  //   privateRouter.pushAndSupply(usdc, 10 ** 6, dai, 1 ether, maker1);
  //   vm.stopPrank();

  //   uint finalize_cost = gas - gasleft();
  //   console.log("deep pull: %d, finalize: %d", deep_pull_cost, finalize_cost);
  //   console.log("shallow push: %d", shallow_push_cost);
  //   console.log("Strat gasreq (%d), mockup (%d)", GASREQ, deep_pull_cost + finalize_cost);
  //   assertApproxEqAbs(deep_pull_cost + finalize_cost, GASREQ, 200, "Check new gas cost");
  // }

  // function test_push_token_increases_first_minter_shares() public {
  //   deal($(dai), maker1, 10 ** 18);
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 10 ** 18);
  //   assertEq(privateRouter.sharesOf(dai, maker1), 10 ** privateRouter.OFFSET(), "Incorrect first shares");
  // }

  // function test_pull_token_decreases_last_minter_shares_to_zero() public {
  //   deal($(dai), maker1, 10 ** 18);
  //   vm.startPrank(maker1);
  //   privateRouter.push(dai, maker1, 10 ** 18);
  //   privateRouter.pull(dai, maker1, 10 ** 18, true);
  //   vm.stopPrank();
  //   assertEq(privateRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  // }

  // function test_push0() public {
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 0);
  //   assertEq(privateRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  // }

  // function test_pull0() public {
  //   vm.prank(maker1);
  //   privateRouter.pull(dai, maker1, 0, true);
  //   assertEq(privateRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  // }

  // function test_donation_in_underlying_increases_user_shares(uint96 donation) public {
  //   deal($(dai), maker1, 1 * 10 ** 18);
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 1 * 10 ** 18);

  //   deal($(dai), maker2, 4 * 10 ** 18);
  //   vm.prank(maker2);
  //   privateRouter.push(dai, maker2, 4 * 10 ** 18);

  //   deal($(dai), maker1, donation);
  //   vm.prank(maker1);
  //   dai.transfer($(privateRouter), donation);

  //   uint expectedBalance = (uint(5) * 10 ** 18 + uint(donation)) / 5;
  //   uint reserveBalance = privateRouter.balanceOfReserve(dai, maker1);
  //   assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker1");

  //   expectedBalance = uint(4) * (5 * 10 ** 18 + uint(donation)) / 5;
  //   vm.prank(maker2);
  //   reserveBalance = privateRouter.balanceOfReserve(dai, maker2);
  //   assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker2");
  // }

  // function test_strict_pull_with_insufficient_funds_throws_as_expected() public {
  //   vm.expectRevert("AavePooledRouter/insufficientFunds");
  //   vm.prank(maker1);
  //   privateRouter.pull(dai, maker1, 1, true);
  // }

  // function test_non_strict_pull_with_insufficient_funds_throws_as_expected() public {
  //   vm.expectRevert("AavePooledRouter/insufficientFunds");
  //   deal($(dai), maker1, 10);
  //   vm.prank(maker1);
  //   privateRouter.push(dai, maker1, 10);
  //   vm.prank(maker1);
  //   privateRouter.pull(dai, maker1, 11, false);
  // }

  // function test_strict_pull_transfers_only_amount_and_pulls_all_from_aave() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   // router has no weth on buffer and 1 weth on aave
  //   uint oldAWeth = privateRouter.overlying(weth).balanceOf($(privateRouter));
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, true);
  //   vm.stopPrank();
  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect maker balance");
  //   assertEq(weth.balanceOf($(privateRouter)), oldAWeth - pulled, "Incorrect router balance");
  //   assertEq(privateRouter.overlying(weth).balanceOf($(privateRouter)), 0, "Incorrect aave balance");
  // }

  // function test_non_strict_pull_transfers_whole_balance() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, true);
  //   vm.stopPrank();
  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect balance");
  // }

  // function test_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   vm.stopPrank();
  //   // small donation
  //   deal($(weth), $(privateRouter), 10);

  //   uint oldAWeth = privateRouter.overlying(weth).balanceOf($(privateRouter));
  //   vm.prank(maker1);
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, true);

  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
  //   assertEq(weth.balanceOf($(privateRouter)), oldAWeth - pulled + 10, "Incorrect aWeth balance");
  // }

  // function test_non_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   vm.stopPrank();
  //   // donation
  //   deal($(weth), $(privateRouter), 10);

  //   privateRouter.overlying(weth).balanceOf($(privateRouter));
  //   vm.prank(maker1);
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, false);

  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
  //   assertEq(privateRouter.overlying(weth).balanceOf($(privateRouter)), 0, "Incorrect aWeth balance");
  // }

  // function test_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   vm.stopPrank();
  //   deal($(weth), $(privateRouter), 1 ether);

  //   uint oldAWeth = privateRouter.overlying(weth).balanceOf($(privateRouter));
  //   vm.prank(maker1);
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, true);

  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
  //   assertEq(privateRouter.overlying(weth).balanceOf($(privateRouter)), oldAWeth, "Incorrect aWeth balance");
  // }

  // function test_non_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
  //   deal($(weth), maker1, 1 ether);
  //   vm.startPrank(maker1);
  //   privateRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
  //   vm.stopPrank();
  //   deal($(weth), $(privateRouter), 1 ether);

  //   uint oldAWeth = privateRouter.overlying(weth).balanceOf($(privateRouter));
  //   vm.prank(maker1);
  //   uint pulled = privateRouter.pull(weth, maker1, 0.5 ether, true);

  //   assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
  //   assertEq(privateRouter.overlying(weth).balanceOf($(privateRouter)), oldAWeth, "Incorrect aWeth balance");
  // }

  // function test_claim_rewards() public {
  //   address[] memory assets = new address[](3);
  //   assets[0] = address(privateRouter.overlying(usdc));
  //   assets[1] = address(privateRouter.overlying(weth));
  //   assets[2] = address(privateRouter.overlying(dai));
  //   vm.prank(deployer);
  //   (address[] memory rewardsList, uint[] memory claimedAmounts) = privateRouter.claimRewards(assets);
  //   for (uint i; i < rewardsList.length; i++) {
  //     console.logAddress(rewardsList[i]);
  //     console.log(claimedAmounts[i]);
  //   }
  // }

  // function test_checkList_throws_for_tokens_that_are_not_listed_on_aave() public {
  //   TestToken tkn = new TestToken(
  //     $(this),
  //     "wen token",
  //     "WEN",
  //     42
  //   );
  //   vm.prank(maker1);
  //   tkn.approve({spender: $(privateRouter), amount: type(uint).max});

  //   vm.expectRevert("AavePooledRouter/tokenNotLendableOnAave");
  //   vm.prank(maker1);
  //   privateRouter.checkList(IERC20($(tkn)), maker1);
  // }

  // function empty_pool(IERC20 token, address id) internal {
  //   // empty usdc reserve
  //   uint bal = privateRouter.balanceOfReserve(token, id);
  //   if (bal > 0) {
  //     vm.startPrank(address(makerContract));
  //     privateRouter.pull(token, owner, bal, true);
  //     vm.stopPrank();
  //   }
  //   assertEq(privateRouter.balanceOfReserve(token, id), 0, "Non empty balance");

  //   assertEq(token.balanceOf($(privateRouter)), 0, "Non empty buffer");
  //   assertEq(privateRouter.overlying(token).balanceOf($(privateRouter)), 0, "Non empty pool");
  // }

  // function test_overflow_shares(uint96 amount_) public {
  //   uint amount = uint(amount_);
  //   empty_pool(usdc, owner);
  //   empty_pool(usdc, maker1);
  //   empty_pool(usdc, maker2);

  //   deal($(usdc), maker1, amount + 1);
  //   // maker1 deposits 1 wei and gets 10**OFFSET shares
  //   vm.prank(maker1);
  //   privateRouter.push(usdc, maker1, 1);
  //   // maker1 now deposits max uint104
  //   vm.prank(maker1);
  //   privateRouter.push(usdc, maker1, amount);

  //   // computation below should not throw
  //   assertEq(privateRouter.balanceOfReserve(usdc, maker1), amount + 1, "Incorrect balance");
  // }

  // function test_underflow_shares_6dec(uint96 deposit_, uint96 donation_) public {
  //   empty_pool(usdc, owner);
  //   empty_pool(usdc, maker1);
  //   empty_pool(usdc, maker2);

  //   uint deposit = uint(deposit_);
  //   uint donation = uint(donation_);
  //   vm.assume(deposit > 10 ** 5); // assume deposits at least 10-^2 tokens with 6 decimals
  //   vm.assume(donation < deposit * 10_000);

  //   deal($(usdc), maker1, donation + 1);
  //   vm.prank(maker1);
  //   privateRouter.push(usdc, maker1, 1);

  //   vm.prank(maker1);
  //   usdc.transfer($(privateRouter), donation);

  //   deal($(usdc), maker2, deposit);
  //   vm.prank(maker2);
  //   privateRouter.push(usdc, maker2, deposit);

  //   assertApproxEqRel(deposit, privateRouter.balanceOfReserve(usdc, maker2), 10 ** 13); // error not worth than 10^-7% of the deposit
  // }

  // function test_underflow_shares_18dec(uint96 deposit_, uint96 donation_) public {
  //   empty_pool(weth, owner);
  //   empty_pool(weth, maker1);
  //   empty_pool(weth, maker2);

  //   uint deposit = uint(deposit_);
  //   uint donation = uint(donation_);
  //   vm.assume(deposit > 10 ** 13); // deposits at least 10^-5 ether
  //   vm.assume(donation < deposit * 10_000);

  //   deal($(weth), maker1, donation + 1);
  //   vm.prank(maker1);
  //   privateRouter.push(weth, maker1, 1);

  //   vm.prank(maker1);
  //   weth.transfer($(privateRouter), donation);

  //   deal($(weth), maker2, deposit);
  //   vm.prank(maker2);
  //   privateRouter.push(weth, maker2, deposit);

  //   assertApproxEqRel(deposit, privateRouter.balanceOfReserve(weth, maker2), 10 ** 5); // error not worth than 10^-15% of the deposit
  // }

  // function test_allExternalFunctions_differentCallers_correctAuth() public {
  //   // Arrange
  //   bytes[] memory selectors =
  //     AllMethodIdentifiersTest.getAllMethodIdentifiers(vm, "/out/AavePooledRouter.sol/AavePooledRouter.json");

  //   assertGt(selectors.length, 0, "Some functions should be loaded");

  //   for (uint i = 0; i < selectors.length; i++) {
  //     // Assert that all are called - to decode the selector search in the abi file
  //     vm.expectCall(address(privateRouter), selectors[i]);
  //   }

  //   address admin = freshAddress("newAdmin");
  //   vm.prank(deployer);
  //   privateRouter.setAdmin(admin);

  //   address manager = freshAddress("newManager");
  //   vm.prank(admin);
  //   privateRouter.setAaveManager(manager);

  //   // Act/assert - invoke all functions - if any are missing, add them.

  //   // No auth
  //   privateRouter.ADDRESS_PROVIDER();
  //   privateRouter.OFFSET();
  //   privateRouter.POOL();
  //   privateRouter.aaveManager();
  //   privateRouter.admin();
  //   privateRouter.routerGasreq();
  //   privateRouter.balanceOfReserve(dai, maker1);
  //   privateRouter.sharesOf(dai, maker1);
  //   privateRouter.totalBalance(dai);
  //   privateRouter.totalShares(dai);
  //   privateRouter.isBound(maker1);
  //   privateRouter.overlying(dai);
  //   privateRouter.checkAsset(dai);
  //   vm.prank(maker1);
  //   privateRouter.checkList(dai, maker1);

  //   CheckAuthArgs memory args;
  //   args.callee = $(privateRouter);
  //   args.callers = dynamic([address($(mgv)), maker1, maker2, admin, manager, $(this)]);
  //   args.revertMessage = "AccessControlled/Invalid";

  //   // Maker or admin
  //   args.allowed = dynamic([address(maker1), maker2, admin]);
  //   checkAuth(args, abi.encodeCall(privateRouter.flushBuffer, (dai, true)));
  //   checkAuth(args, abi.encodeCall(privateRouter.activate, dai));

  //   // Only admin
  //   args.allowed = dynamic([address(admin)]);
  //   address freshMaker = freshAddress("newMaker");
  //   checkAuth(args, abi.encodeCall(privateRouter.setAdmin, admin));
  //   checkAuth(args, abi.encodeCall(privateRouter.bind, freshMaker));
  //   checkAuth(args, abi.encodeWithSignature("unbind(address)", freshMaker));

  //   // Only Makers
  //   deal($(dai), maker1, 1 * 10 ** 18);
  //   deal($(dai), maker2, 1 * 10 ** 18);
  //   args.allowed = dynamic([address(maker1), maker2]);
  //   checkAuth(args, abi.encodeCall(privateRouter.push, (dai, maker1, 1000)));
  //   checkAuth(args, abi.encodeCall(privateRouter.pull, (dai, maker1, 100, true)));
  //   checkAuth(args, abi.encodeCall(privateRouter.flush, (new IERC20[](0), owner)));
  //   checkAuth(args, abi.encodeCall(privateRouter.pushAndSupply, (dai, 0, dai, 0, owner)));
  //   checkAuth(args, abi.encodeCall(privateRouter.withdraw, (dai, maker1, 100)));

  //   checkAuth(args, abi.encodeWithSignature("unbind()"));

  //   // Only manager
  //   args.allowed = dynamic([address(manager)]);
  //   checkAuth(args, abi.encodeCall(privateRouter.enterMarket, new IERC20[](0)));
  //   checkAuth(args, abi.encodeCall(privateRouter.claimRewards, dynamic([address(privateRouter.overlying(dai))])));
  //   checkAuth(args, abi.encodeCall(privateRouter.revokeLenderApproval, dai));
  //   checkAuth(args, abi.encodeCall(privateRouter.exitMarket, weth));

  //   // Both manager and admin
  //   args.allowed = dynamic([address(manager), admin]);
  //   checkAuth(args, abi.encodeCall(privateRouter.setAaveManager, manager));
  // }
}
