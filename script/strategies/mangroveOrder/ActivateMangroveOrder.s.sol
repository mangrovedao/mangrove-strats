// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "@mgv/forge-std/console.sol";
import {Script2} from "@mgv/lib/Script2.sol";
import {MangroveOrder, RL} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Allows MangroveOrder to trade on the tokens given in argument.

    mgvOrder: address of MangroveOrder contract
    tkns: array of token addresses to activate
   
    The TKNS env variable should be given as a comma-separated list of names (known by ens) or addresses.
    For instance:

  TKNS="DAI,USDC,WETH,DAI_AAVE,USDC_AAVE,WETH_AAVE" forge script --fork-url mumbai ActivateMangroveOrder*/

contract ActivateMangroveOrder is Deployer {
  function run() public {
    string[] memory tkns = vm.envString("TKNS", ",");
    IERC20[] memory tokens = new IERC20[](tkns.length);
    for (uint i = 0; i < tkns.length; ++i) {
      tokens[i] = IERC20(fork.get(tkns[i]));
    }

    innerRun({mgvOrder: MangroveOrder(envAddressOrName("MANGROVE_ORDER", "MangroveOrder")), tokens: tokens});
  }

  function innerRun(MangroveOrder mgvOrder, IERC20[] memory tokens) public {
    console.log("MangroveOrder (%s) is acting of Mangrove (%s)", address(mgvOrder), address(mgvOrder.MGV()));
    console.log("Activating tokens...");
    for (uint i = 0; i < tokens.length; ++i) {
      console.log("%s (%s)", tokens[i].symbol(), address(tokens[i]));
      broadcast();
      mgvOrder.activate(tokens[i]);
    }
    console.log("done!");
  }
}
