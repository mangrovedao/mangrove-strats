// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {MangroveOrder, IERC20, IMangrove} from "mgv_strat_src/strategies/MangroveOrder.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveOrderDeployer} from "./MangroveOrderDeployer.s.sol";

/**
 * Mumbai specific deployment of MangroveOrderDeployer
 */
contract MumbaiMangroveOrderDeployer is Deployer {
  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    new MangroveOrderDeployer().innerRun({
      permit2: IPermit2(envAddressOrName("PERMIT2", "Permit2")),
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster())
    });
  }
}
