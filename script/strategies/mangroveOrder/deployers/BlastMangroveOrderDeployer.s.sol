// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MangroveOrderDeployer} from "./MangroveOrderDeployer.s.sol";
import {Script, console} from "@mgv/forge-std/Script.sol";
import {IERC20, IMangrove, MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {BlastRouterProxyFactory} from "@mgv-strats/src/strategies/chains/blast/routers/BlastRouterProxyFactory.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";
import {BlastMangroveOrder} from "@mgv-strats/src/strategies/chains/blast/BlastMangroveOrder.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

import {StdCheats} from "@mgv/forge-std/StdCheats.sol";

// NB: Must be executed with the --skip-simulation --slow flags:
// - Skip simulation because the Blast predeploys are not known by forge
// - Slow because Blast Sepolia (and maybe Blast) fails to execute transactions
//     that interact with a contract that was deployed in the same block.
contract BlastMangroveOrderDeployer is MangroveOrderDeployer, StdCheats {
  IBlast public blastContract;
  IBlastPoints public blastPointsContract;

  address public blastGovernor;
  address public blastPointsOperator;

  function run() public override {
    blastContract = IBlast(envAddressOrName("BLAST_CONTRACT", "Blast"));
    blastPointsContract = IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints"));
    blastGovernor = envAddressOrName("BLAST_GOVERNOR", "BlastGovernor");
    blastPointsOperator = envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator");

    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster()),
      routerProxyFactory: BlastRouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory")),
      _blastContract: IBlast(envAddressOrName("BLAST_CONTRACT", "Blast")),
      _blastPointsContract: IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints")),
      _blastGovernor: envAddressOrName("BLAST_GOVERNOR", "BlastGovernor"),
      _blastPointsOperator: envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator")
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    address admin,
    BlastRouterProxyFactory routerProxyFactory,
    IBlast _blastContract,
    address _blastGovernor,
    IBlastPoints _blastPointsContract,
    address _blastPointsOperator
  ) public {
    blastContract = _blastContract;
    blastPointsContract = _blastPointsContract;
    blastGovernor = _blastGovernor;
    blastPointsOperator = _blastPointsOperator;

    // forge doesn't know the Blast predeploys, so we need to deploy them.
    // Otherwise, the script fails (even with the --skip-simulation flag).
    deployCodeTo("Blast.sol", address(blastContract));
    deployCodeTo("BlastPoints.sol", address(blastPointsContract));

    super.innerRun({mgv: mgv, admin: admin, routerProxyFactory: routerProxyFactory});
  }

  function deployRouter() internal override returns (SmartRouter router) {
    broadcast();
    if (forMultisig) {
      router = new BlastSmartRouter{salt: salt}({
        blastContract: blastContract,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    } else {
      router = new BlastSmartRouter({
        blastContract: blastContract,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    }
  }

  function deployMangroveOrder(
    IMangrove mgv,
    address admin,
    BlastRouterProxyFactory routerProxyFactory,
    SmartRouter routerImplementation
  ) internal virtual returns (MangroveOrder mgvOrder) {
    BlastSmartRouter blastRouterImplementation = BlastSmartRouter(address(routerImplementation));

    broadcast();
    if (forMultisig) {
      mgvOrder = new BlastMangroveOrder{salt: salt}({
        mgv: mgv,
        factory: routerProxyFactory,
        deployer: admin,
        routerImplementation: blastRouterImplementation,
        blastContract: blastContract,
        blastGovernor: blastGovernor,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    } else {
      mgvOrder = new BlastMangroveOrder({
        mgv: mgv,
        factory: routerProxyFactory,
        deployer: admin,
        routerImplementation: blastRouterImplementation,
        blastContract: blastContract,
        blastGovernor: blastGovernor,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    }
  }
}
