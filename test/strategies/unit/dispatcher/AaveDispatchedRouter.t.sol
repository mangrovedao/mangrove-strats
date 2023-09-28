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

contract AaveDispatchedRouterTest is OfferDispatcherTest {
  bool internal useForkAave = true;
  IERC20 internal dai;

  IPoolAddressesProvider internal ADDRESS_PROVIDER;
  IPool internal POOL;

  function setUp() public virtual override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PolygonFork();
    }
    super.setUp();

    vm.prank(deployer);
    makerContract.activate(dynamic([dai]));

    // vm.startPrank(deployer);
    // dai.approve({spender: $(privateRouter), amount: type(uint).max});
    // weth.approve({spender: $(privateRouter), amount: type(uint).max});
    // usdc.approve({spender: $(privateRouter), amount: type(uint).max});
    // vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    super.fundStrat();
    vm.startPrank(owner);
    // approve and supply weth to aave
    weth.approve(address(POOL), type(uint).max);
    POOL.supply(address(weth), 1 ether, owner, 0);
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal virtual override {
    dai = useForkAave ? dai = TestToken(fork.get("DAI")) : new TestToken($(this),"Dai","Dai",options.base.decimals);
    address aave = useForkAave
      ? fork.get("Aave")
      : address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])));

    ADDRESS_PROVIDER = IPoolAddressesProvider(aave);
    POOL = IPool(ADDRESS_PROVIDER.getPool());

    vm.prank(deployer);
    AaveDispatchedRouter router = new AaveDispatchedRouter({
      routerGasreq_: 1_000_000,
      addressesProvider: aave,
      interestRateMode: 2, // variable
      storage_key: "router.aave.1"
    });

    IERC20 aWETH = IERC20(POOL.getReserveData(address(weth)).aTokenAddress);
    IERC20 aUSDC = IERC20(POOL.getReserveData(address(usdc)).aTokenAddress);

    vm.startPrank(owner);
    aWETH.approve(address(makerContract.router()), type(uint).max);
    aUSDC.approve(address(makerContract.router()), type(uint).max);
    offerDispatcher.setRoute(weth, owner, router);
    offerDispatcher.setRoute(usdc, owner, router);
    vm.stopPrank();
  }
}
