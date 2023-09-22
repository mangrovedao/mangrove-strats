// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

/**
 * @notice Prints the order book
 */

/*
   BASE=WETH QUOTE=USDC TICK_SCALE=1 forge script PrintOrderBook --fork-url $LOCALHOST_URL --private-key $MUMBAI_PRIVATE_KEY
 */
contract PrintOrderBook is Deployer, MangroveTest {
  function run() public {
    reader = MgvReader(envAddressOrName("MGV_READER", "MgvReader"));
    mgv = IMangrove(envAddressOrName("MGV", "Mangrove"));

    olKey = OLKey(envAddressOrName("BASE"), envAddressOrName("QUOTE"), vm.envUint("TICK_SCALE"));
    printOfferList(olKey);
    printOfferList(olKey.flipped());
  }
}
