// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {BlastRouterProxyFactory} from "@mgv-strats/src/strategies/chains/blast/routers/BlastRouterProxyFactory.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

import {StdCheats} from "@mgv/forge-std/StdCheats.sol";

/*  Deploys a BlastRouterProxyFactory instance */
// NB: Must be executed with the --skip-simulation --slow flags:
// - Skip simulation because the Blast predeploys are not known by forge
// - Slow because Blast Sepolia (and maybe Blast) fails to execute transactions
//     that interact with a contract that was deployed in the same block.
contract BlastRouterProxyFactoryDeployer is Deployer {
  function run() public {
    innerRun({
      admin: envAddressOrName("ADMIN", broadcaster()),
      _blastContract: IBlast(envAddressOrName("BLAST_CONTRACT", "Blast")),
      _blastPointsContract: IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints")),
      _blastGovernor: envAddressOrName("BLAST_GOVERNOR", "BlastGovernor"),
      _blastPointsOperator: envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator")
    });
    outputDeployment();
  }

  function innerRun(
    address admin,
    IBlast _blastContract,
    address _blastGovernor,
    IBlastPoints _blastPointsContract,
    address _blastPointsOperator
  ) public {
    broadcast();
    BlastRouterProxyFactory factory = new BlastRouterProxyFactory({
      _admin: admin,
      blastContract: _blastContract,
      blastGovernor: _blastGovernor,
      blastPointsContract: _blastPointsContract,
      blastPointsOperator: _blastPointsOperator
    });
    fork.set("RouterProxyFactory", address(factory));
    console.log("factory deployed", address(factory));
  }
}
