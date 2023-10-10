// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.18;

import {AbstractDispatchedRouter, OfferLogicTest, IERC20, TestToken, console} from "./AbstractDispatchedRouter.sol";
import {
  AavePrivateRouter,
  DataTypes,
  ReserveConfiguration
} from "mgv_strat_src/strategies/routers/integrations/AavePrivateRouter.sol";
import {AaveDispatchedRouter} from "mgv_strat_src/strategies/routers/integrations/dispatched/AaveDispatchedRouter.sol";

import {PolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";
import {PoolAddressProviderMock} from "mgv_strat_script/toy/AaveMock.sol";

import {IPool} from "mgv_strat_src/strategies/vendor/aave/v3/IPool.sol";
import {IPoolAddressesProvider} from "mgv_strat_src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {SimpleRouter, AbstractRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";

import {Dispatcher} from "mgv_strat_src/strategies/routers/integrations/Dispatcher.sol";

contract AaveDispatchedRouterTest is AbstractDispatchedRouter {
  bool internal useForkAave = true;
  IERC20 internal dai;

  IPoolAddressesProvider internal ADDRESS_PROVIDER;
  IPool internal POOL;

  AaveDispatchedRouter internal aaveRouter;
  SimpleRouter internal simpleRouter;

  function setUp() public virtual override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PolygonFork();
    }
    super.setUp();

    vm.prank(deployer);
    makerContract.activate(dynamic([dai]));
  }

  function fundStrat() internal virtual override {
    super.fundStrat();
    vm.startPrank(owner);
    // approve and supply weth to aave
    weth.approve(address(POOL), type(uint).max);
    POOL.supply(address(weth), 1 ether, owner, 0);
    vm.stopPrank();
  }

  function getOverlying(IERC20 token) internal view returns (IERC20) {
    return IERC20(POOL.getReserveData(address(token)).aTokenAddress);
  }

  function setupLiquidityRouting() internal virtual override {
    dai = useForkAave ? dai = TestToken(fork.get("DAI")) : new TestToken($(this),"Dai","Dai",options.base.decimals);
    address aave = useForkAave
      ? fork.get("Aave")
      : address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])));

    ADDRESS_PROVIDER = IPoolAddressesProvider(aave);
    POOL = IPool(ADDRESS_PROVIDER.getPool());

    vm.startPrank(deployer);
    aaveRouter = new AaveDispatchedRouter({
      routerGasreq_: 1_000_000,
      addressesProvider: aave,
      interestRateMode: 2, // variable
      storage_key: "router.aave.1"
    });

    simpleRouter = new SimpleRouter();

    bytes4[] memory mutators = new bytes4[](1);
    mutators[0] = aaveRouter.setAaveCreditLine.selector;

    bytes4[] memory accessors = new bytes4[](1);
    accessors[0] = aaveRouter.getAaveCreditLine.selector;

    offerDispatcher.initializeRouter(address(aaveRouter), mutators, accessors);

    vm.stopPrank();

    IERC20 aWETH = getOverlying(weth);
    IERC20 aUSDC = getOverlying(usdc);

    vm.startPrank(owner);
    aWETH.approve(address(makerContract.router()), type(uint).max);
    aUSDC.approve(address(makerContract.router()), type(uint).max);
    // Setting aave routers only for outbound (weth) by default
    // otherwise simple router will be used
    offerDispatcher.setRoute(weth, owner, aaveRouter);
    offerDispatcher.setRoute(usdc, owner, aaveRouter);
    vm.stopPrank();
  }

  function getCreditLine(address owner, IERC20 token) internal view returns (uint8) {
    bytes4 sig = aaveRouter.getAaveCreditLine.selector;
    bytes memory data = offerDispatcher.querySpecifics(sig, owner, token, "");
    return abi.decode(data, (uint8));
  }

  function setCreditLine(address owner, IERC20 token, uint8 creditLine) internal {
    bytes4 sig = aaveRouter.setAaveCreditLine.selector;
    bytes memory data = abi.encode(creditLine);
    vm.prank(owner);
    offerDispatcher.mutateSpecifics(sig, owner, token, data);
  }

  // must be made in order to have aave rewards taken into account
  function test_owner_balance_is_updated_when_trade_succeeds() public virtual override {
    uint balOut = makerContract.tokenBalance(weth, owner);
    uint balIn = makerContract.tokenBalance(usdc, owner);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    assertApproxEqAbs(makerContract.tokenBalance(weth, owner), balOut - (takergot + fee), 1, "incorrect out balance");
    assertEq(makerContract.tokenBalance(usdc, owner), balIn + takergave, "incorrect in balance");
  }

  function test_token_balance_of() public {
    IERC20 aWETH = getOverlying(weth);
    uint aWethBalance = aWETH.balanceOf(owner);
    uint startTokenBalance = makerContract.tokenBalance(weth, owner);

    // Here, owner is supposed to have only aWETH and no WETH
    assertEq(aWethBalance, startTokenBalance, "incorrect token balance");

    deal($(weth), owner, 1 ether);

    uint wethBalance = weth.balanceOf(owner);
    uint endTokenBalance = makerContract.tokenBalance(weth, owner);
    assertEq(wethBalance + aWethBalance, endTokenBalance, "incorrect token balance");
  }

  function test_take_underlying_first() public {
    deal($(weth), owner, 1 ether);

    IERC20 aWETH = getOverlying(weth);
    uint startAWethBalance = aWETH.balanceOf(owner);

    uint balOut = makerContract.tokenBalance(weth, owner);
    uint balIn = makerContract.tokenBalance(usdc, owner);

    assertGe(balOut, startAWethBalance + 0.5 ether, "Must have at least 0.5 ether of WETH to cover order");

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    assertApproxEqAbs(makerContract.tokenBalance(weth, owner), balOut - (takergot + fee), 1, "incorrect out balance");
    assertApproxEqAbs(makerContract.tokenBalance(usdc, owner), balIn + takergave, 1, "incorrect in balance");

    uint endAWethBalance = aWETH.balanceOf(owner);
    assertEq(endAWethBalance, startAWethBalance, "Suppose to have same amount of aWETH");
  }

  function test_partial_balance_of_underlying() public {
    deal($(weth), owner, 0.2 ether);

    IERC20 aWETH = getOverlying(weth);
    uint startAWethBalance = aWETH.balanceOf(owner);
    uint startWethBalance = weth.balanceOf(owner);

    assertLt(startWethBalance, 0.5 ether, "Should not be able to cover entire offer");

    uint balOut = makerContract.tokenBalance(weth, owner);
    uint balIn = makerContract.tokenBalance(usdc, owner);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    assertApproxEqAbs(makerContract.tokenBalance(weth, owner), balOut - (takergot + fee), 1, "incorrect out balance");
    assertEq(makerContract.tokenBalance(usdc, owner), balIn + takergave, "incorrect in balance");

    uint endAWethBalance = aWETH.balanceOf(owner);
    uint endWethBalance = weth.balanceOf(owner);

    assertEq(endWethBalance, 0, "Should have taken all WETH first");
    assertApproxEqAbs(startAWethBalance - endAWethBalance, 0.5 ether - startWethBalance, 1, "incorrect trade output");
  }

  function test_get_set_credit_line() public {
    uint8 creditLine = getCreditLine(owner, weth);
    assertEq(creditLine, 100, "incorrect credit line");

    setCreditLine(owner, weth, 50);
    creditLine = getCreditLine(owner, weth);
    assertEq(creditLine, 50, "incorrect credit line");

    vm.expectRevert("AaveDispatchedRouter/InvalidCreditLineDecrease");
    setCreditLine(owner, weth, 101);
  }

  function test_can_withdraw_low_credit_line_no_debt() public {
    setCreditLine(owner, weth, 1);
    uint balOut = makerContract.tokenBalance(weth, owner);
    uint balIn = makerContract.tokenBalance(usdc, owner);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    assertApproxEqAbs(makerContract.tokenBalance(weth, owner), balOut - (takergot + fee), 1, "incorrect out balance");
    assertApproxEqAbs(makerContract.tokenBalance(usdc, owner), balIn + takergave, 1, "incorrect in balance");
  }

  function test_cannot_withdraw_above_credit_line() public {
    vm.prank(owner);

    POOL.borrow(address(usdc), 1000 * 10 ** 6, 2, 0, owner);

    setCreditLine(owner, weth, 0);

    // expect to fail
    performTrade(false);

    setCreditLine(owner, weth, 100);

    // should work again
    performTrade(true);
  }
}
