// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {SimpleAbracadabraLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAbracadabraLogic.sol";
import {AbracadabraAddressProvider} from "@mgv-strats/src/strategies/integrations/abracadabra/AddressProvider.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/*  Deploys a SimeplAbracadabraLogic instance */
contract SimpleAbracadabraLogicDeployer is Deployer {
  function run() public {
    innerRun({
      addressProvider: AbracadabraAddressProvider(
        envAddressOrName("ABRACADABRA_ADDRESS_PROVIDER", "AbracadabraAddressProvider")
        )
    });
    outputDeployment();
  }

  function innerRun(AbracadabraAddressProvider addressProvider) public {
    broadcast();
    SimpleAbracadabraLogic simpleAbracadabraLogic = new SimpleAbracadabraLogic(addressProvider);
    fork.set("SimpleAbracadabraLogic", address(simpleAbracadabraLogic));
    console.log("SimpleAbracadabraLogic deployed", address(simpleAbracadabraLogic));
  }
}
