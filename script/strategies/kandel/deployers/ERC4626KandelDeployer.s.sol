// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {ERC4626Kandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626Kandel.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {KandelSower} from "../KandelSower.s.sol";

/**
 * @notice deploys a Kandel instance on a given market
 * @dev since the max number of price slot Kandel can use is an immutable, one should deploy Kandel on a large price range.
 * @dev Example: WRITE_DEPLOY=true BASE=WETH QUOTE=USDC forge script --fork-url $LOCALHOST_URL ERC4626KandelDeployer --broadcast --private-key $MUMBAI_PRIVATE_KEY
 */
contract ERC4626KandelDeployer is Deployer {
  ERC4626Kandel public current;

  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      olKeyBaseQuote: OLKey(envAddressOrName("BASE"), envAddressOrName("QUOTE"), vm.envUint("TICK_SPACING")),
      gasreq: 200_000,
      name: envHas("NAME") ? vm.envString("NAME") : "",
      routerParams: Direct.RouterParams({
        routerImplementation: AbstractRouter(vm.envAddress("ERC4626_ROUTER")),
        fundOwner: vm.envAddress("FUND_OWNER"),
        strict: true
      })
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove deployment.
   * @param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
   * @param gasreq the gas required for the offer logic
   * @param name The name to register the deployed Kandel instance under. If empty, a name will be generated
   */
  function innerRun(
    IMangrove mgv,
    OLKey memory olKeyBaseQuote,
    uint gasreq,
    string memory name,
    Direct.RouterParams memory routerParams
  ) public {
    broadcast();
    current = new ERC4626Kandel(mgv, olKeyBaseQuote, gasreq, routerParams);

    string memory kandelName = new KandelSower().getName(name, olKeyBaseQuote, false);
    fork.set(kandelName, address(current));
  }
}
