// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IERC20, IMangrove} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {MangroveOrderWithPermit2} from "mgv_strat_src/strategies/MangroveOrderWithPermit2.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveOrderWithPermit2Deployer} from "./MangroveOrderWithPermit2Deployer.s.sol";

/**
 * Mumbai specific deployment of MangroveOrderWithPermit2
 */
contract MumbaiMangroveOrderWithPermit2Deployer is Deployer {
  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    new MangroveOrderWithPermit2Deployer().innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      permit2: IPermit2(envAddressOrName("PERMIT2", "Permit2")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster())
    });
  }
}
