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

  uint internal constant GASREQ = 550_100;

  event SetAaveManager(address);
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

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
      overhead: 1_000_000,
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

  function test_supply_error_is_logged() public {
    TestToken pixieDust = new TestToken({
      admin: address(this),
      name: "Pixie Dust",
      symbol: "PXD",
      _decimals: uint8(18)
    });

    deal($(pixieDust), address(makerContract), 1 ether);
    vm.prank(address(makerContract));
    pixieDust.approve($(privateRouter), type(uint).max);
    vm.prank(deployer);
    privateRouter.activate(pixieDust);

    expectFrom($(privateRouter));
    emit LogAaveIncident({asset: address(pixieDust), maker: address(makerContract), aaveReason: "noReason"});
    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(pixieDust, 1 ether, pixieDust, 0);
    // although aave refused the deposit, funds should be on the router
    assertEq(privateRouter.balanceOfReserve(pixieDust, owner), 1 ether, "Incorrect balance on router");
  }

  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  function test_exit_market() public {
    // pooled router has entered weth and usdc market when first supplying
    expectFrom(address(privateRouter.POOL()));
    emit ReserveUsedAsCollateralDisabled($(dai), $(privateRouter));
    vm.prank(deployer);
    privateRouter.exitMarket(dai);
  }

  function test_reenter_market() public {
    vm.prank(deployer);
    privateRouter.exitMarket(dai);

    expectFrom(address(privateRouter.POOL()));
    emit ReserveUsedAsCollateralEnabled($(dai), $(privateRouter));
    vm.prank(deployer);
    privateRouter.enterMarket(dynamic([IERC20(dai)]));
  }

  function test_deposit_on_aave_maintains_reserve_balance() public {
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    // this pushes usdc on the router w/o supplying to the pool
    privateRouter.push(usdc, address(makerContract), 10 ** 6);

    uint reserveBalance = privateRouter.balanceOfReserve(usdc, address(makerContract));

    vm.prank(address(makerContract));
    privateRouter.flushBuffer(usdc);

    assertApproxEqAbs(
      reserveBalance, privateRouter.balanceOfReserve(usdc, address(makerContract)), 1, "Incorrect reserve balance"
    );
  }

  function test_mockup_marketOrder_gas_cost() public {
    deal($(usdc), address(makerContract), 2 * 10 ** 6);

    // emulates a push from offer logic
    vm.startPrank(address(makerContract));
    uint gas = gasleft();
    privateRouter.push(usdc, address(makerContract), 10 ** 6);
    vm.stopPrank();

    uint shallow_push_cost = gas - gasleft();

    vm.prank(address(makerContract));
    privateRouter.flushBuffer(usdc);

    vm.startPrank(address(makerContract));
    gas = gasleft();
    /// this emulates a `get` from the offer logic
    privateRouter.pull(weth, address(makerContract), 0.5 ether, false);
    vm.stopPrank();

    uint deep_pull_cost = gas - gasleft();

    // this emulates posthook
    vm.startPrank(address(makerContract));
    gas = gasleft();
    privateRouter.pushAndSupply(usdc, 10 ** 6, weth, 0.5 ether);
    vm.stopPrank();

    uint finalize_cost = gas - gasleft();
    console.log("deep pull: %d, finalize: %d", deep_pull_cost, finalize_cost);
    console.log("shallow push: %d", shallow_push_cost);
    console.log("Strat gasreq (%d), mockup (%d)", GASREQ, deep_pull_cost + finalize_cost);
    assertApproxEqAbs(deep_pull_cost + finalize_cost, GASREQ, 200, "Check new gas cost");
  }

  function test_checkList_throws_for_tokens_that_are_not_listed_on_aave() public {
    TestToken tkn = new TestToken(
      $(this),
      "wen token",
      "WEN",
      42
    );
    vm.prank(address(makerContract));
    tkn.approve({spender: $(privateRouter), amount: type(uint).max});

    vm.prank(address(makerContract));
    vm.expectRevert("AavePooledRouter/tokenNotLendableOnAave");
    privateRouter.checkList(IERC20($(tkn)), address(makerContract));
  }

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
