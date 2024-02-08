// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a RouterProxyFactory instance */
contract RouterProxyFactoryDeployer is Deployer {
  function run() public {
    innerRun();
    outputDeployment();
  }

  function innerRun() public {
    broadcast();
    RouterProxyFactory factory = new RouterProxyFactory();
    fork.set("RouterProxyFactory", address(factory));
    console.log("factory deployed", address(factory));
  }
}
