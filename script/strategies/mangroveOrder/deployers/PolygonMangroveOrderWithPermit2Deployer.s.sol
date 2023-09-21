// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IERC20, IMangrove} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {MangroveOrderWithPermit2} from "mgv_strat_src/strategies/MangroveOrderWithPermit2.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveOrderWithPermit2Deployer} from "./MangroveOrderWithPermit2Deployer.s.sol";

/**
 * Polygon specific deployment of MangroveOrderWithPermit2
 */
contract PolygonMangroveOrderWithPermit2Deployer is Deployer {
  MangroveOrderWithPermit2Deployer public mangroveOrderDeployer;

  function run() public {
    fork.set("Permit2", envAddressOrName("PERMIT2", "Permit2"));
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveOrderDeployer = new MangroveOrderWithPermit2Deployer();
    mangroveOrderDeployer.innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      permit2: IPermit2(fork.get("Permit2")),
      admin: fork.get("MgvGovernance")
    });
  }
}
