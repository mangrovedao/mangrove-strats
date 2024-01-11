// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMangrove} from "@mgv/src/IMangrove.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveAmplifierDeployer, RouterProxyFactory, SmartRouter} from "./MangroveAmplifierDeployer.s.sol";

/**
 * Arbitrum specific deployment of MangroveOrder
 */
contract ArbitrumMangroveOrderDeployer is Deployer {
  MangroveAmplifierDeployer public mangroveAmplifierDeployer;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveAmplifierDeployer = new MangroveAmplifierDeployer();
    mangroveAmplifierDeployer.innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      routerProxyFactory: RouterProxyFactory(fork.get("RouterProxyFactory")),
      routerImplementation: SmartRouter(fork.get("MangroveOrder-Router"))
    });
  }
}
