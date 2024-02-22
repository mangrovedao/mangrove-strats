// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {SimpleAbracadabraLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAbracadabraLogic.sol";
import {ICauldronV4} from "@mgv-strats/src/strategies/vendor/abracadabra/interfaces/ICauldronV4.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/*  Deploys a SimeplAbracadabraLogic instance */
contract SimpleAbracadabraLogicDeployer is Deployer {
  function run() public {
    innerRun({
      cauldron: ICauldronV4(envAddressOrName("ABRACADABRA_CAULDRON", "AbracadabraCauldron")),
      mim: IERC20(envAddressOrName("MIM", "mim"))
    });
    outputDeployment();
  }

  function innerRun(IERC20 mim, ICauldronV4 cauldron) public {
    broadcast();
    SimpleAbracadabraLogic simpleAbracadabraLogic = new SimpleAbracadabraLogic(mim, cauldron);
    fork.set("SimpleAbracadabraLogic", address(simpleAbracadabraLogic));
    console.log("SimpleAbracadabraLogic deployed", address(simpleAbracadabraLogic));
  }
}
