// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {SimpleBeefyLogicFactory} from "@mgv-strats/src/strategies/routing_logic/beefy/SimpleBeefyLogicFactory.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a SimpleBeefyLogicFactoryDeployer instance */
contract SimpleBeefyLogicFactoryDeployer is Deployer {
  function run() public {
    innerRun();
    outputDeployment();
  }

  function innerRun() public {
    broadcast();
    SimpleBeefyLogicFactory simpleBeefyLogicFactory = new SimpleBeefyLogicFactory();
    fork.set("SimpleBeefyLogicFactory", address(simpleBeefyLogicFactory));
    console.log("SimpleBeefyLogicFactory deployed", address(simpleBeefyLogicFactory));
  }
}
