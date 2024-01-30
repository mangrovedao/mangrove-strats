// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {
  SimpleBeefyLogicFactory,
  IBeefyVaultV7
} from "@mgv-strats/src/strategies/routing_logic/beefy/SimpleBeefyLogicFactory.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Adds vaults and deployes SimpleBeefyLogic instance from the factory */
contract AddSimpleBeefyLogic is Deployer {
  function run() public {
    address[] memory vaults = vm.envAddress("VAULTS", ",");
    IBeefyVaultV7[] memory vaultsAddresses = new IBeefyVaultV7[](vaults.length);
    for (uint i = 0; i < vaults.length; ++i) {
      vaultsAddresses[i] = IBeefyVaultV7(vaults[i]);
    }

    innerRun({
      simpleBeefyLogicFactory: SimpleBeefyLogicFactory(
        envAddressOrName("SIMPLE_BEEFY_LOGIC_FACTORY", "SimpleBeefyLogicFactory")
        ),
      vaults: vaultsAddresses
    });
  }

  function innerRun(SimpleBeefyLogicFactory simpleBeefyLogicFactory, IBeefyVaultV7[] memory vaults) public {
    broadcast();
    simpleBeefyLogicFactory.addLogics(vaults);
  }
}
