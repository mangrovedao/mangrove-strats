// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferLogicTest, IERC20, TestToken, console} from "./OfferLogic.t.sol";
import {
  AavePrivateRouter,
  DataTypes,
  ReserveConfiguration
} from "mgv_strat_src/strategies/routers/integrations/AavePrivateRouter.sol";
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";
import {PoolAddressProviderMock} from "mgv_strat_script/toy/AaveMock.sol";

contract AavePrivateRouterNoBufferTest is OfferLogicTest {
  bool internal useForkAave = true;

  AavePrivateRouter internal privateRouter;

  uint internal expectedGasreq = 548_700;

  event SetAaveManager(address);
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

  IERC20 internal dai;

  uint internal bufferSize;
  uint internal interestRate = 2; // stable borrowing not enabled on polygon

  function setUp() public virtual override {
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
    assertApproxEqAbs(privateRouter.balanceOfReserve(dai, owner), collateralAmount, 1, "Incorrect collateral balance");
  }

  // this test overrides the one in OfferLogic.t.sol with borrow specific strat balances
  function test_owner_balance_is_updated_when_trade_succeeds() public virtual override {
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
    console.log("Strat gasreq (%d), mockup (%d)", expectedGasreq, deep_pull_cost + finalize_cost);
    assertApproxEqAbs(deep_pull_cost + finalize_cost, expectedGasreq, 1000, "Check new gas cost");
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
    privateRouter.checkList(IERC20($(tkn)), address(makerContract), address(makerContract));
  }

  function test_pulled_collateral_is_consistent_with_buffer(uint8 dice) public virtual {
    vm.assume(dice < 2);
    bool strict = (dice == 1);
    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(dai);

    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(dai, address(makerContract), 10, strict);
    /// no buffer imposes strict <=> !strict because router will always withdraw `amount` from the pool
    assertEq(pulled, 10, "Incorrect pulled amount");
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(dai);
    assertEq(bal_.local, 0, "Incorrect buffer on the router");
    assertApproxEqAbs(bal_.onPool, bal.onPool - pulled, 1, "No collateral should be left on the pool");
    assertEq(dai.balanceOf(address(makerContract)), pulled, "Unexpected amount of dai on the maker contract");
  }

  function test_push_and_supply_repays_debt() public {
    // router borrows as a response to the pull request (because it does not supply weth)
    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(weth, address(makerContract), 1 ether, true);
    assertEq(weth.balanceOf(address(makerContract)), 1 ether, "Pull failed");
    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(weth);
    assertTrue(bal.debt > 0, "Router should be endebted");
    // router should empty its weth buffer and repay debt
    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(weth, pulled, usdc, 0);
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(weth);
    assertEq(bal_.debt, 0, "Router should no longer be endebted");
  }

  function test_push_and_supply_more_than_debt_increases_supply() public {
    deal(address(weth), address(makerContract), 1 ether);
    // router borrows as a response to the pull request (because it does not supply weth)
    vm.prank(address(makerContract));
    privateRouter.pull(weth, address(makerContract), 1 ether, true);

    // router should empty its weth buffer and repay debt
    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(weth, 2 ether, usdc, 0);

    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(weth);
    assertEq(bal.debt, 0, "Router should no longer be endebted");
    assertApproxEqAbs(bal.onPool, 1 ether, 1, "Incomplete supply on pool");
  }
}

contract AavePrivateRouterFullBufferTest is AavePrivateRouterNoBufferTest {
  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PolygonFork();
    }
    bufferSize = 100;
    super.setUp();
  }

  function test_pulled_collateral_is_consistent_with_buffer(uint8 dice) public override {
    vm.assume(dice < 2);
    bool strict = dice == 1;
    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(dai);

    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(dai, address(makerContract), 10, strict);
    assertEq(pulled, strict ? 10 : bal.liquid, "incorrect pulled amount");
    // checking:
    // * 1 wei of DAI is transferred to maker contract
    // * 1 DAI - 1 wei remains as buffer on the router
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(dai);
    assertEq(bal_.local, strict ? bal.onPool - 10 : 0, "Incorrect buffer on the router");
    assertEq(bal_.onPool, 0, "No collateral should be left on the pool");
    assertEq(dai.balanceOf(address(makerContract)), pulled, "Unexpected amount of dai on the maker contract");
  }

  // this test overrides the one in OfferLogic.t.sol with borrow specific strat balances
  function test_owner_balance_is_updated_when_trade_succeeds() public override {
    AavePrivateRouter.AssetBalances memory balWethBefore = privateRouter.assetBalances(weth);
    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");
    AavePrivateRouter.AssetBalances memory balUsdc = privateRouter.assetBalances(usdc);

    // all incoming USDCs should be on the router (DirectTester does not ask for depositing on AAVE)
    assertEq(balUsdc.onPool, 0, "There should be no USDC balance on pool");
    assertEq(balUsdc.local, takergave, "Incorrect USDC on the router");
    assertEq(balUsdc.debt, 0, "There should be no USDC debt");

    AavePrivateRouter.AssetBalances memory balWeth = privateRouter.assetBalances(weth);
    // contract borrowed everything that could be borrowed (full buffer) and DirectTester does not repay debt on posthook
    assertApproxEqAbs(balWeth.debt, balWethBefore.creditLine, 1, "Incorrect WETH debt");
    assertEq(balWeth.local, balWethBefore.creditLine - (takergot + fee), "Incorrect residual WETH on the router");
    assertEq(balWeth.onPool, 0, "There should be no WETH on the pool");
  }

  // this test makes sure that it is safe to borrow to the limit, because a malicious taker cannot prevent the router to repay at the end of the marketOrder
  function test_can_repay_debt_even_if_supply_cap_is_reached() public {
    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(weth, address(makerContract), 10 ether, true);

    assertEq(weth.balanceOf(address(makerContract)), pulled, "Wrong amount of ether pulled");

    DataTypes.ReserveData memory data = privateRouter.reserveData(weth);
    uint supplyCap = ReserveConfiguration.getSupplyCap(data.configuration);
    uint currentSupply = IERC20(data.aTokenAddress).totalSupply();

    // pushing reserve supply to the max
    deal($(weth), address(this), supplyCap * 10 ** 18 - currentSupply);
    weth.approve(address(privateRouter.POOL()), type(uint).max);
    privateRouter.POOL().supply(address(weth), weth.balanceOf(address(this)) - 1 ether, address(this), 0);
    assertEq(IERC20(data.aTokenAddress).totalSupply() / 10 ** 18, supplyCap - 1, "Supply cap not reached");

    // repaying debt
    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(weth, 10 ether, usdc, 0);

    assertEq(privateRouter.assetBalances(weth).debt, 0, "debt was not repaid");
  }
}

contract AavePrivateRouterHalfBufferTest is AavePrivateRouterNoBufferTest {
  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PolygonFork();
    }
    bufferSize = 50;
    super.setUp();
  }

  function test_pulled_collateral_is_consistent_with_buffer(uint8 dice) public override {
    vm.assume(dice < 2);
    bool strict = dice == 1;
    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(dai);

    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(dai, address(makerContract), 10, strict);
    assertEq(pulled, strict ? 10 : bal.onPool / 2, "Incorrect pulled amount");
    // checking:
    // * 1 wei of DAI is transferred to maker contract
    // * 1 DAI - 1 wei remains as buffer on the router
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(dai);
    assertEq(bal_.local, bal.onPool / 2 - pulled, "Incorrect buffer on the router");
    assertApproxEqAbs(bal_.onPool, bal.onPool / 2, 1, "Incorrect collateral left on the pool");
    assertEq(dai.balanceOf(address(makerContract)), pulled, "Unexpected amount of dai on the maker contract");
  }

  // this test overrides the one in OfferLogic.t.sol with borrow specific strat balances
  function test_owner_balance_is_updated_when_trade_succeeds() public override {
    AavePrivateRouter.AssetBalances memory balWethBefore = privateRouter.assetBalances(weth);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");
    AavePrivateRouter.AssetBalances memory balUsdc = privateRouter.assetBalances(usdc);

    // all incoming USDCs should be on the router (DirectTester does not ask for depositing on AAVE)
    assertEq(balUsdc.onPool, 0, "There should be no USDC balance on pool");
    assertEq(balUsdc.local, takergave, "Incorrect USDC on the router");
    assertEq(balUsdc.debt, 0, "There should be no USDC debt");

    AavePrivateRouter.AssetBalances memory balWeth = privateRouter.assetBalances(weth);
    // contract borrowed half of borrow capacity (half buffer) and DirectTester does not repay debt on posthook
    assertApproxEqAbs(balWeth.debt, balWethBefore.creditLine / 2, 1, "Incorrect WETH debt");
    assertEq(balWeth.local, balWethBefore.creditLine / 2 - (takergot + fee), "Incorrect residual WETH on the router");
    assertEq(balWeth.onPool, 0, "There should be no WETH on the pool");
  }
}
