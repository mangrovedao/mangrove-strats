// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {BlastRouterProxyFactory} from "@mgv-strats/src/strategies/chains/blast/routers/BlastRouterProxyFactory.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a BlastRouterProxyFactory instance */
contract RouterProxyFactoryDeployer is Deployer {
  function run() public {
    innerRun({chief: envAddressOrName("CHIEF", broadcaster())});
    outputDeployment();
  }

  function innerRun(address chief) public {
    broadcast();
    BlastRouterProxyFactory factory = new BlastRouterProxyFactory(chief);
    fork.set("RouterProxyFactory", address(factory));
    console.log("factory deployed", address(factory));
  }
}
