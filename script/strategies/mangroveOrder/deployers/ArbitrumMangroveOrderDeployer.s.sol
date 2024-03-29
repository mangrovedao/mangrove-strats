// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMangrove} from "@mgv/src/IMangrove.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveOrderDeployer, RouterProxyFactory} from "./MangroveOrderDeployer.s.sol";

/**
 * Arbitrum specific deployment of MangroveOrder
 */
contract ArbitrumMangroveOrderDeployer is Deployer {
  MangroveOrderDeployer public mangroveOrderDeployer;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveOrderDeployer = new MangroveOrderDeployer();
    mangroveOrderDeployer.innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      admin: fork.get("MgvGovernance"),
      routerProxyFactory: RouterProxyFactory(fork.get("RouterProxyFactory"))
    });
  }
}
