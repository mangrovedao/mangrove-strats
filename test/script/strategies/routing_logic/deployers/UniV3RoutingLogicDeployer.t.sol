// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";

import {
  UniV3RoutingLogicDeployer,
  UniswapV3RoutingLogic,
  UniswapV3Manager,
  INonfungiblePositionManager,
  RouterProxyFactory,
  AbstractRouter
} from "@mgv-strats/script/strategies/routing_logic/deployers/uni-v3/UniV3RoutingLogicDeployer.s.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {Univ3Deployer} from "@mgv-strats/src/toy_strategies/utils/Univ3Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {RouterProxyFactoryDeployer} from
  "@mgv-strats/script/strategies/routerProxyFactory/deployers/RouterProxyFactoryDeployer.s.sol";
import {
  MangroveOrderDeployer,
  MangroveOrder
} from "@mgv-strats/script/strategies/mangroveOrder/deployers/MangroveOrderDeployer.s.sol";

contract Univ3LogicDeployerTest is Deployer, Test2, Univ3Deployer {
  UniV3RoutingLogicDeployer salDeployer;
  address chief;

  function setUp() public {
    chief = freshAddress("admin");

    deployUniv3();

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
    (new RouterProxyFactoryDeployer()).innerRun();
    (new MangroveOrderDeployer()).innerRun(
      IMangrove(payable(fork.get("Mangrove"))), chief, RouterProxyFactory(fork.get("RouterProxyFactory"))
    );
    salDeployer = new UniV3RoutingLogicDeployer();
  }

  function test_normal_deploy() public {
    salDeployer.innerRun({
      positionManager: positionManager,
      factory: RouterProxyFactory(fork.get("RouterProxyFactory")),
      implementation: AbstractRouter(fork.get("MangroveOrder-Router")),
      forkName: "MyFork"
    });

    // SimpleAaveLogic sal = SimpleAaveLogic(fork.get("SimpleAaveLogic"));

    // assertEq(sal.INTEREST_RATE_MODE(), interestRateMode);
  }
}
