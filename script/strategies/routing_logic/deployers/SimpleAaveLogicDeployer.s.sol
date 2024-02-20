// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from
  "@mgv-strats/src/strategies/vendor/aave/v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a SimeplAaveLogic instance */
contract SimpleAaveLogicDeployer is Deployer {
  function run() public {
    innerRun({
      addressProvider: IPoolAddressesProvider(envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider")),
      interestRateMode: vm.envUint("INTEREST_RATE_MODE")
    });
    outputDeployment();
  }

  function innerRun(IPoolAddressesProvider addressProvider, uint interestRateMode) public {
    broadcast();
    SimpleAaveLogic simpleAaveLogic = new SimpleAaveLogic(addressProvider, interestRateMode);
    fork.set("SimpleAaveLogic", address(simpleAaveLogic));
    console.log("SimpleAaveLogic deployed", address(simpleAaveLogic));
  }
}
