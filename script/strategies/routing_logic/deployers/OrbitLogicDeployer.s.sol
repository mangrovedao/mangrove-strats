// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {OrbitLogic} from "@mgv-strats/src/strategies/routing_logic/orbit/OrbitLogic.sol";
import {OrbitSpaceStation} from "@orbit-protocol/contracts/SpaceStation.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a OrbitLogic instance */
contract OrbitLogicDeployer is Deployer {
  function run() public {
    innerRun({spaceStation: OrbitSpaceStation(vm.envAddress("SPACE_STATION"))});
    outputDeployment();
  }

  function innerRun(OrbitSpaceStation spaceStation) public {
    broadcast();
    OrbitLogic orbitLogic = new OrbitLogic(spaceStation);
    fork.set("OrbitLogic", address(orbitLogic));
    console.log("OrbitLogic deployed", address(orbitLogic));
  }
}
