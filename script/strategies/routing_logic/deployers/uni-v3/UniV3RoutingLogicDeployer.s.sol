// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {UniswapV3Manager} from "@mgv-strats/src/strategies/routing_logic/restaking/uni-v3/UniswapV3Manager.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {UniswapV3RoutingLogic} from
  "@mgv-strats/src/strategies/routing_logic/restaking/uni-v3/UniswapV3RoutingLogic.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a UniswapV3Logic instance */
contract UniV3RoutingLogicDeployer is Deployer {
  function run() public {
    innerRun({
      positionManager: INonfungiblePositionManager(vm.envAddress("UNISWAP_V3_POSITION_MANAGER")),
      factory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory")),
      implementation: AbstractRouter(envAddressOrName("SMART_ROUTER_IMPLEMENTATION", "MangroveOrder-Router")),
      forkName: vm.envString("FORK_NAME")
    });
    outputDeployment();
  }

  function innerRun(
    INonfungiblePositionManager positionManager,
    RouterProxyFactory factory,
    AbstractRouter implementation,
    string memory forkName
  ) public {
    broadcast();
    UniswapV3Manager uniswapV3Manager = new UniswapV3Manager(positionManager, factory, implementation);
    string memory managerName = string.concat("UniswapV3Manager-", forkName);
    fork.set(managerName, address(uniswapV3Manager));
    console.log("UniswapV3Manager deployed", address(uniswapV3Manager));

    broadcast();
    UniswapV3RoutingLogic uniswapV3RoutingLogic = new UniswapV3RoutingLogic(uniswapV3Manager);
    string memory logicName = string.concat("UniswapV3RoutingLogic-", forkName);
    fork.set(logicName, address(uniswapV3RoutingLogic));
    console.log("UniswapV3RoutingLogic deployed", address(uniswapV3RoutingLogic));
  }
}
