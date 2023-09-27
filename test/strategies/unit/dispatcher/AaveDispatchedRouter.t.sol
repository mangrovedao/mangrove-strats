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

contract AaveDispatchedRouterTest is OfferDispatcherTest {
  bool internal useForkAave = true;
  IERC20 internal dai;

  function setupLiquidityRouting() internal virtual override {
    dai = useForkAave ? dai = TestToken(fork.get("DAI")) : new TestToken($(this),"Dai","Dai",options.base.decimals);
    address aave = useForkAave
      ? fork.get("Aave")
      : address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])));

    vm.prank(deployer);
    AaveDispatchedRouter router = new AaveDispatchedRouter({
      routerGasreq_: 1_000_000,
      addressesProvider: aave,
      interestRateMode: 2, // variable
      storage_key: "router.aave.1"
    });

    vm.startPrank(owner);
    offerDispatcher.setRoute(weth, owner, router);
    offerDispatcher.setRoute(usdc, owner, router);
    vm.stopPrank();
  }
}
