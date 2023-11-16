// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {console} from "@mgv/forge-std/Script.sol";
import {
  IMangrove, KandelSeeder, Kandel
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {
  AaveKandelSeeder,
  AaveKandel
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {CoreKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {RouterProxyFactory, Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";

/**
 * @notice deploys a Kandel seeder
 */

contract KandelSeederDeployer is Deployer, Test2 {
  function run() public {
    bool deployAaveKandel = true;
    bool deployKandel = true;
    try vm.envBool("DEPLOY_AAVE_KANDEL") returns (bool deployAaveKandel_) {
      deployAaveKandel = deployAaveKandel_;
    } catch {}
    try vm.envBool("DEPLOY_KANDEL") returns (bool deployKandel_) {
      deployKandel = deployKandel_;
    } catch {}
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      addressesProvider: envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider"),
      aaveKandelGasreq: 628_000,
      kandelGasreq: 128_000,
      deployAaveKandel: deployAaveKandel,
      deployKandel: deployKandel,
      testBase: IERC20(envAddressOrName("TEST_BASE")),
      testQuote: IERC20(envAddressOrName("TEST_QUOTE"))
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    address addressesProvider,
    uint aaveKandelGasreq,
    uint kandelGasreq,
    bool deployAaveKandel,
    bool deployKandel,
    IERC20 testBase,
    IERC20 testQuote
  ) public returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) {
    //FIXME: what tick spacing? Why do we assume an open market?
    uint tickSpacing = 1;
    OLKey memory olKeyBaseQuote = OLKey(address(testBase), address(testQuote), tickSpacing);

    if (deployKandel) {
      prettyLog("Deploying Kandel seeder...");
      broadcast();
      seeder = new KandelSeeder(mgv, kandelGasreq);
      fork.set("KandelSeeder", address(seeder));

      console.log("Deploying Kandel instance for code verification and to use as proxy for KandelLib...");
      broadcast();
      Kandel kandel = new Kandel(mgv, olKeyBaseQuote, 1);
      fork.set("KandelLib", address(kandel));
      smokeTest(mgv, olKeyBaseQuote, seeder, AbstractRouter(address(0)));
    }
    if (deployAaveKandel) {
      prettyLog("Deploying AaveKandel seeder...");
      // Bug workaround: Foundry has a bug where the nonce is not incremented when AaveKandelSeeder is deployed.
      //                 We therefore ensure that this happens.
      uint64 nonce = vm.getNonce(broadcaster());
      broadcast();
      aaveSeeder = new AaveKandelSeeder(mgv, addressesProvider, aaveKandelGasreq);
      // Bug workaround: See comment above `nonce` further up
      if (nonce == vm.getNonce(broadcaster())) {
        vm.setNonce(broadcaster(), nonce + 1);
      }
      fork.set("AaveKandelSeeder", address(aaveSeeder));
      fork.set("AavePooledRouter", address(aaveSeeder.AAVE_ROUTER()));

      console.log("Deploying AaveKandel instance for code verification...");
      prettyLog("Deploying AaveKandel instance...");
      AbstractRouter router = AbstractRouter(address(aaveSeeder.AAVE_ROUTER()));
      console.log("Seeder's router:", address(router));
      broadcast();
      new AaveKandel(mgv, olKeyBaseQuote, aaveKandelGasreq, Direct.RouterParams({
        routerImplementation: router,
        fundOwner: address(0),
        strict: true
      }));
      smokeTest(mgv, olKeyBaseQuote, aaveSeeder, aaveSeeder.AAVE_ROUTER());
    }

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
      // starting smoke test with 10 inbound on Kandel
      deal({to: address(kandel), token: olKeyBaseQuote.inbound_tkn, give: 10});

      vm.startPrank(address(kandel));
      // push should take 5 inbound (out of 10) from kandel and send it to router
      uint pushed = kandel.router().push(
        RL.createOrder({token: IERC20(olKeyBaseQuote.inbound_tkn), amount: 5, fundOwner: kandel.FUND_OWNER()})
      );
      require(pushed == 5, "smoke test: push failed");
      // pull should take 1 outbound from router and send it to kandel
      uint pulled = kandel.router().pull(
        RL.createOrder({token: IERC20(olKeyBaseQuote.inbound_tkn), amount: 1, fundOwner: kandel.FUND_OWNER()}), true
      );
      require(pulled == 1, "smoke test: pull failed");
      vm.stopPrank();
    }
  }
}
