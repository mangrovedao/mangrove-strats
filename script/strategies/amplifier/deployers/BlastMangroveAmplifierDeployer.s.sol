// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MangroveAmplifierDeployer} from "./MangroveAmplifierDeployer.s.sol";
import {
  MangroveAmplifier,
  IMangrove,
  RouterProxyFactory,
  SmartRouter
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {BlastMangroveAmplifier} from "@mgv-strats/src/strategies/chains/blast/BlastMangroveAmplifier.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

import {StdCheats} from "@mgv/forge-std/StdCheats.sol";

// NB: Must be executed with the --skip-simulation --slow flags:
// - Skip simulation because the Blast predeploys are not known by forge
// - Slow because Blast Sepolia (and maybe Blast) fails to execute transactions
//     that interact with a contract that was deployed in the same block.
contract BlastMangroveAmplifierDeployer is MangroveAmplifierDeployer, StdCheats {
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
      routerProxyFactory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory")),
      routerImplementation: SmartRouter(envAddressOrName("MANGROVEORDER_ROUTER", "SmartRouter")),
      _blastContract: IBlast(envAddressOrName("BLAST_CONTRACT", "Blast")),
      _blastPointsContract: IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints")),
      _blastGovernor: envAddressOrName("BLAST_GOVERNOR", "BlastGovernor"),
      _blastPointsOperator: envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator")
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    RouterProxyFactory routerProxyFactory,
    SmartRouter routerImplementation,
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

    super.innerRun({mgv: mgv, routerProxyFactory: routerProxyFactory, routerImplementation: routerImplementation});
  }

  function deployMangroveAmplifier(
    IMangrove mgv,
    RouterProxyFactory routerProxyFactory,
    SmartRouter _routerImplementation
  ) internal override returns (MangroveAmplifier mgvAmp) {
    BlastSmartRouter routerImplementation = BlastSmartRouter(address(_routerImplementation));
    broadcast();
    if (forMultisig) {
      mgvAmp = new BlastMangroveAmplifier{salt: salt}({
        mgv: mgv,
        factory: routerProxyFactory,
        routerImplementation: routerImplementation,
        blastContract: blastContract,
        blastGovernor: blastGovernor,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    } else {
      mgvAmp = new BlastMangroveAmplifier({
        mgv: mgv,
        factory: routerProxyFactory,
        routerImplementation: routerImplementation,
        blastContract: blastContract,
        blastGovernor: blastGovernor,
        blastPointsContract: blastPointsContract,
        blastPointsOperator: blastPointsOperator
      });
    }
  }
}
