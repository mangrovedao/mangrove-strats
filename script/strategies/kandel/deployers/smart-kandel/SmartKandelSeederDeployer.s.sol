// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "@mgv/forge-std/Script.sol";
import {
  IMangrove,
  SmartKandelSeeder,
  SmartKandel,
  RouterProxyFactory
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/SmartKandelSeeder.sol";
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {CoreKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";

/**
 * @notice deploys a Kandel seeder
 */
contract SmartKandelSeederDeployer is Deployer, Test2 {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      kandelGasreq: 128_000,
      factory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY")),
      routerImplementation: AbstractRouter(envAddressOrName("MANGROVEORDER_ROUTER")),
      testBase: IERC20(envAddressOrName("TEST_BASE")),
      testQuote: IERC20(envAddressOrName("TEST_QUOTE"))
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    uint kandelGasreq,
    RouterProxyFactory factory,
    AbstractRouter routerImplementation,
    IERC20 testBase,
    IERC20 testQuote
  ) public returns (SmartKandelSeeder seeder) {
    // Tick spacing is irrelevant, only used to deploy for verification and to use as a library
    uint tickSpacing = 1;
    OLKey memory olKeyBaseQuote = OLKey(address(testBase), address(testQuote), tickSpacing);

    prettyLog("Deploying Kandel seeder...");
    broadcast();
    seeder = new SmartKandelSeeder(mgv, kandelGasreq, factory, routerImplementation);
    fork.set("SmartKandelSeeder", address(seeder));

    smokeTest(
      mgv, olKeyBaseQuote, seeder, AbstractRouter(factory.computeProxyAddress(address(this), routerImplementation))
    );

    console.log("Deployed!");
  }

  function smokeTest(
    IMangrove mgv,
    OLKey memory olKeyBaseQuote,
    AbstractKandelSeeder kandelSeeder,
    AbstractRouter expectedRouter
  ) internal {
    // Ensure that WETH/DAI market is open on Mangrove
    vm.startPrank(mgv.governance());
    mgv.activate(olKeyBaseQuote, 0, 1, 1);
    mgv.activate(olKeyBaseQuote.flipped(), 0, 1, 1);
    vm.stopPrank();

    CoreKandel kandel = kandelSeeder.sow({olKeyBaseQuote: olKeyBaseQuote, liquiditySharing: true});

    require(kandel.router() == expectedRouter, "Incorrect router address");
    require(kandel.admin() == address(this), "Incorrect admin");
    if (address(expectedRouter) == address(0)) {
      require(kandel.FUND_OWNER() == address(kandel), "Incorrect id");
    } else {
      require(kandel.FUND_OWNER() == kandel.admin(), "Incorrect id");
    }
  }
}
