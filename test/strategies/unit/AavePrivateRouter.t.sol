// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {AbstractRouterTest, IERC20, TestToken} from "./AbstractRouter.t.sol";
import {
  ApprovalInfo,
  AavePrivateRouter,
  DataTypes,
  ReserveConfiguration
} from "mgv_strat_src/strategies/routers/integrations/AavePrivateRouter.sol";
/// could be forking Aave from Ethereum here
import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {PoolAddressProviderMock} from "mgv_strat_script/toy/AaveMock.sol";

import "mgv_lib/Debug.sol";

contract AavePrivateRouterTest is AbstractRouterTest {
  bool internal useForkAave = true;

  AavePrivateRouter internal privateRouter;

  uint internal expectedGasreq = 306_131;

  event SetAaveManager(address);
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

  IERC20 internal dai;

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
    router = new AavePrivateRouter({
      addressesProvider:aave, 
      interestRate:interestRate, 
      overhead: 1_000_000
    });
    router.bind(address(makerContract));
    makerContract.setRouter(router);
    privateRouter = AavePrivateRouter(address(router));
    vm.stopPrank();
    // although reserve is set to deployer the source remains makerContract since privateRouter is always the source of funds
    // having reserve pointing to deployed allows deployer to have multiple strats with the same shares on the router
    owner = deployer;
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE

    uint collateralAmount = 1_000_000 * 10 ** 18;
    deal($(dai), address(makerContract), collateralAmount);
    // router has only been activated for base and quote but is agnostic wrt collateral
    // here we want to use DAI (neither base or quote) as collateral so we need to activate the router to transfer it from the maker contract
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(dai)]));

    vm.prank(address(makerContract));
    privateRouter.pushAndSupply(dai, collateralAmount);
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
    // this pushes usdc on the router w/o supplying to the pool (repays debt if any)
    privateRouter.pushAndSupply(usdc, 10 ** 6);

    uint reserveBalance = privateRouter.balanceOfReserve(usdc, address(makerContract));

    assertApproxEqAbs(
      reserveBalance, privateRouter.balanceOfReserve(usdc, address(makerContract)), 1, "Incorrect reserve balance"
    );
  }

  function test_mockup_marketOrder_gas_cost() public {
    // load useful storage in memory to prevent dummy storage reads
    AavePrivateRouter memoizedRouter = privateRouter;
    ApprovalInfo memory memoizedApprovalInfo = approvalInfo;
    address maker = address(makerContract);
    IERC20 USDC = usdc;
    IERC20 WETH = weth;

    deal($(usdc), address(makerContract), 2 * 10 ** 6);

    // emulates a push from offer logic
    vm.startPrank(maker);
    uint gas = gasleft();
    memoizedRouter.push(USDC, maker, 10 ** 6);
    vm.stopPrank();

    uint shallow_push_cost = gas - gasleft();

    vm.startPrank(maker);
    gas = gasleft();
    /// this emulates a `get` from the offer logic
    memoizedRouter.pull(WETH, maker, 0.5 ether, false, memoizedApprovalInfo);
    vm.stopPrank();
    uint deep_pull_cost = gas - gasleft();

    console.log("deep pull: %d", deep_pull_cost);
    console.log("shallow push: %d", shallow_push_cost);
    console.log("Strat gasreq (%d), mockup (%d)", expectedGasreq, deep_pull_cost);
    assertApproxEqAbs(deep_pull_cost, expectedGasreq, 1000, "Check new gas cost");
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

  function test_pulls_asset() public virtual {
    bool strict = true;
    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(weth, address(makerContract), 10, strict, approvalInfo);
    assertEq(pulled, 10, "Incorrect pulled amount");
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(weth);
    assertEq(bal_.local, 0, "Incorrect buffer on the router");
    assertEq(weth.balanceOf(address(makerContract)), pulled, "Unexpected amount of dai on the maker contract");
    assertEq(bal_.debt, pulled, "Unexpected debt");
  }

  function test_push_repays_debt() public {
    // router borrows as a response to the pull request (because it does not supply weth)
    vm.prank(address(makerContract));
    uint pulled = privateRouter.pull(weth, address(makerContract), 1 ether, true, approvalInfo);
    assertEq(weth.balanceOf(address(makerContract)), 1 ether, "Pull failed");
    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(weth);
    assertTrue(bal.debt > 0, "Router should be endebted");
    // router should empty its weth buffer and repay debt
    vm.prank(address(makerContract));
    privateRouter.push(weth, address(makerContract), pulled);
    AavePrivateRouter.AssetBalances memory bal_ = privateRouter.assetBalances(weth);
    assertEq(bal_.debt, 0, "Router should no longer be endebted");
  }

  function test_push_and_supply_more_than_debt_local_balance() public {
    deal(address(weth), address(makerContract), 1 ether);
    // router borrows as a response to the pull request (because it does not supply weth)
    vm.prank(address(makerContract));
    privateRouter.pull(weth, address(makerContract), 1 ether, true, approvalInfo);

    // router should empty its weth buffer and repay debt
    vm.prank(address(makerContract));
    privateRouter.push(weth, address(makerContract), 2 ether);

    AavePrivateRouter.AssetBalances memory bal = privateRouter.assetBalances(weth);
    assertEq(bal.debt, 0, "Router should no longer be endebted");
    assertApproxEqAbs(bal.local, 1 ether, 1, "Incorrect local balance");
  }
}
