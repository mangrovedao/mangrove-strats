// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {BlastUniswapV3Manager} from "@mgv-strats/src/strategies/chains/blast/routing_logic/BlastUniswapV3Manager.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {UniswapV3RoutingLogic} from
  "@mgv-strats/src/strategies/routing_logic/restaking/uni-v3/UniswapV3RoutingLogic.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {IERC20Rebasing} from "@mgv-strats/src/strategies/vendor/blast/IERC20Rebasing.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/*  Deploys a UniswapV3Logic instance */
contract BlastUniV3RoutingLogicDeployer is Deployer {
  function run() public {
    address[] memory tokens = vm.envAddress("REBASING_TOKENS", ",");
    IERC20Rebasing[] memory rebasingTokens = new IERC20Rebasing[](tokens.length);
    for (uint i = 0; i < tokens.length; i++) {
      rebasingTokens[i] = IERC20Rebasing(tokens[i]);
    }
    innerRun({
      positionManager: INonfungiblePositionManager(vm.envAddress("UNISWAP_V3_POSITION_MANAGER")),
      factory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory")),
      implementation: AbstractRouter(envAddressOrName("SMART_ROUTER_IMPLEMENTATION", "MangroveOrder-Router")),
      forkName: vm.envString("FORK_NAME"),
      tokens: rebasingTokens,
      admin: vm.envAddress("ADMIN"),
      blastContract: IBlast(vm.envAddress("BLAST")),
      pointsContract: IBlastPoints(vm.envAddress("BLAST_POINTS")),
      pointsOperator: vm.envAddress("BLAST_POINTS_OPERATOR"),
      blastGovernor: vm.envAddress("BLAST_GOVERNOR")
    });
    outputDeployment();
  }

  function innerRun(
    INonfungiblePositionManager positionManager,
    RouterProxyFactory factory,
    AbstractRouter implementation,
    string memory forkName,
    IERC20Rebasing[] memory tokens,
    address admin,
    IBlast blastContract,
    IBlastPoints pointsContract,
    address pointsOperator,
    address blastGovernor
  ) public {
    broadcast();
    BlastUniswapV3Manager uniswapV3Manager = new BlastUniswapV3Manager(
      tokens,
      admin,
      positionManager,
      factory,
      implementation,
      pointsContract,
      pointsOperator,
      blastContract,
      blastGovernor
    );
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
