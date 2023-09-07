// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Kandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";
import {KandelSower} from "../KandelSower.s.sol";

/**
 * @notice deploys a Kandel instance on a given market
 * @dev since the max number of price slot Kandel can use is an immutable, one should deploy Kandel on a large price range.
 * @dev Example: WRITE_DEPLOY=true BASE=WETH QUOTE=USDC GASPRICE_FACTOR=10 forge script --fork-url $LOCALHOST_URL KandelDeployer --broadcast --private-key $MUMBAI_PRIVATE_KEY
 */

contract KandelDeployer is Deployer {
  Kandel public current;

  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      olKeyBaseQuote: OLKey(envAddressOrName("BASE"), envAddressOrName("QUOTE"), vm.envUint("TICK_SCALE")),
      gaspriceFactor: vm.envUint("GASPRICE_FACTOR"), // 10 means cover 10x the current gasprice of Mangrove
      gasreq: 200_000,
      name: envHas("NAME") ? vm.envString("NAME") : ""
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove deployment.
   * @param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
   * @param gasreq the gas required for the offer logic
   * @param gaspriceFactor multiplier of Mangrove's gasprice used to compute Kandel's provision
   * @param name The name to register the deployed Kandel instance under. If empty, a name will be generated
   */
  function innerRun(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, uint gaspriceFactor, string memory name)
    public
  {
    (MgvStructs.GlobalPacked global,) = mgv.config(OLKey(address(0), address(0), 0));

    broadcast();
    current = new Kandel(
      mgv,
      olKeyBaseQuote,
      gasreq,
      global.gasprice() * gaspriceFactor,
      broadcaster()
    );

    uint precision = current.PRECISION();
    broadcast();

    string memory kandelName = new KandelSower().getName(name, olKeyBaseQuote, false);
    fork.set(kandelName, address(current));
  }
}
