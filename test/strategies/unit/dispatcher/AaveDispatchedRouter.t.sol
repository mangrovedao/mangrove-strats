// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.18;

import {OfferDispatcherTest, OfferLogicTest, IERC20, TestToken, console} from "./OfferDispatcher.t.sol";
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

contract AaveDispatchedRouterTest is OfferDispatcherTest {
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

    vm.prank(deployer);
    aaveRouter = new AaveDispatchedRouter({
      routerGasreq_: 1_000_000,
      addressesProvider: aave,
      interestRateMode: 2, // variable
      storage_key: "router.aave.1"
    });

    vm.prank(deployer);
    simpleRouter = new SimpleRouter();

    IERC20 aWETH = getOverlying(weth);

    vm.startPrank(owner);
    aWETH.approve(address(makerContract.router()), type(uint).max);
    // Setting aave routers only for outbound (weth) by default
    // otherwise simple router will be used
    offerDispatcher.setRoute(weth, owner, aaveRouter);
    offerDispatcher.setRoute(usdc, owner, simpleRouter);
    vm.stopPrank();
  }

  // must be made in order to have aave rewards taken into account
  function test_owner_balance_is_updated_when_trade_succeeds() public virtual override {
    uint balOut = makerContract.tokenBalance(weth, owner);
    uint balIn = makerContract.tokenBalance(usdc, owner);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    assertGe(makerContract.tokenBalance(weth, owner), balOut - (takergot + fee), "incorrect out balance");
    assertEq(makerContract.tokenBalance(usdc, owner), balIn + takergave, "incorrect in balance");
  }
}
