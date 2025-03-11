// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "@mgv/forge-std/Script.sol";
import {
  IMangrove, KandelSeeder, Kandel
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {
  AaveKandelSeeder,
  AaveKandel,
  IPoolAddressesProvider
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {
  ERC4626Kandel,
  ERC4626KandelSeeder
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626KandelSeeder.sol";
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
contract KandelSeederDeployer is Deployer, Test2 {
  function run() public {
    bool deployAaveKandel = true;
    bool deployERC4626Kandel = true;
    bool deployKandel = true;

    try vm.envBool("DEPLOY_AAVE_KANDEL") returns (bool deployAaveKandel_) {
      deployAaveKandel = deployAaveKandel_;
    } catch {}

    try vm.envBool("DEPLOY_ERC4626_KANDEL") returns (bool deployERC4626Kandel_) {
      deployERC4626Kandel = deployERC4626Kandel_;
    } catch {}

    try vm.envBool("DEPLOY_KANDEL") returns (bool deployKandel_) {
      deployKandel = deployKandel_;
    } catch {}

    // Create the parameters struct
    DeploymentParams memory params = DeploymentParams({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      addressesProvider: IPoolAddressesProvider(envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider")),
      aaveKandelGasreq: 628_000,
      erc4626KandelGasreq: 628_000,
      kandelGasreq: 128_000,
      deployAaveKandel: deployAaveKandel,
      deployERC4626Kandel: deployERC4626Kandel,
      deployKandel: deployKandel,
      testBase: IERC20(envAddressOrName("TEST_BASE")),
      testQuote: IERC20(envAddressOrName("TEST_QUOTE"))
    });

    innerRun(params);
    outputDeployment();
  }

  struct DeploymentParams {
    IMangrove mgv;
    IPoolAddressesProvider addressesProvider;
    uint aaveKandelGasreq;
    uint erc4626KandelGasreq;
    uint kandelGasreq;
    bool deployAaveKandel;
    bool deployERC4626Kandel;
    bool deployKandel;
    IERC20 testBase;
    IERC20 testQuote;
  }

  function innerRun(DeploymentParams memory params)
    public
    returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder, ERC4626KandelSeeder erc4626Seeder)
  {
    // Tick spacing is irrelevant, only used to deploy for verification and to use as a library
    uint tickSpacing = 1;
    OLKey memory olKeyBaseQuote = OLKey(address(params.testBase), address(params.testQuote), tickSpacing);

    if (params.deployKandel) {
      prettyLog("Deploying Kandel seeder...");
      broadcast();
      seeder = new KandelSeeder(params.mgv, params.kandelGasreq);
      fork.set("KandelSeeder", address(seeder));

      console.log("Deploying Kandel instance for code verification and to use as proxy for KandelLib...");
      broadcast();
      Kandel kandel = new Kandel(params.mgv, olKeyBaseQuote, 1);
      // Write the kandel's address so it can be used as a library to call createGeometricDistribution
      fork.set("KandelLib", address(kandel));

      smokeTest(
        SmokeTestParams({
          mgv: params.mgv,
          olKeyBaseQuote: olKeyBaseQuote,
          kandelSeeder: seeder,
          expectedRouter: AbstractRouter(address(0))
        })
      );
    }

    if (params.deployAaveKandel) {
      prettyLog("Deploying AaveKandel seeder...");
      // Bug workaround: Foundry has a bug where the nonce is not incremented when AaveKandelSeeder is deployed.
      //                 We therefore ensure that this happens.
      uint64 nonce = vm.getNonce(broadcaster());
      broadcast();
      aaveSeeder = new AaveKandelSeeder(params.mgv, params.addressesProvider, params.aaveKandelGasreq);
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
      new AaveKandel(
        params.mgv,
        olKeyBaseQuote,
        params.aaveKandelGasreq,
        Direct.RouterParams({routerImplementation: router, fundOwner: address(0), strict: true})
      );
      smokeTest(
        SmokeTestParams({
          mgv: params.mgv,
          olKeyBaseQuote: olKeyBaseQuote,
          kandelSeeder: aaveSeeder,
          expectedRouter: aaveSeeder.AAVE_ROUTER()
        })
      );
    }

    if (params.deployERC4626Kandel) {
      prettyLog("Deploying ERC4626Kandel seeder...");
      // Bug workaround: Foundry has a bug where the nonce is not incremented when AaveKandelSeeder is deployed.
      //                 We therefore ensure that this happens.
      uint64 nonce = vm.getNonce(broadcaster());
      broadcast();
      erc4626Seeder = new ERC4626KandelSeeder(params.mgv, params.erc4626KandelGasreq);
      // Bug workaround: See comment above `nonce` further up
      if (nonce == vm.getNonce(broadcaster())) {
        vm.setNonce(broadcaster(), nonce + 1);
      }
      fork.set("ERC4626KandelSeeder", address(erc4626Seeder));
      fork.set("ERC4626Rounter", address(erc4626Seeder.ERC4626_ROUTER()));

      console.log("Deploying ERC4626Kandel instance for code verification...");
      prettyLog("Deploying ERC4626Kandel instance...");
      AbstractRouter router = AbstractRouter(address(erc4626Seeder.ERC4626_ROUTER()));
      console.log("Seeder's router:", address(router));
      broadcast();
      new ERC4626Kandel(
        params.mgv,
        olKeyBaseQuote,
        params.aaveKandelGasreq,
        Direct.RouterParams({routerImplementation: router, fundOwner: address(0), strict: true})
      );
      smokeTest(
        SmokeTestParams({
          mgv: params.mgv,
          olKeyBaseQuote: olKeyBaseQuote,
          kandelSeeder: erc4626Seeder,
          expectedRouter: erc4626Seeder.ERC4626_ROUTER()
        })
      );
    }

    console.log("Deployed!");
  }

  struct SmokeTestParams {
    IMangrove mgv;
    OLKey olKeyBaseQuote;
    AbstractKandelSeeder kandelSeeder;
    AbstractRouter expectedRouter;
  }

  function smokeTest(SmokeTestParams memory params) internal {
    // Ensure that market is open on Mangrove
    vm.startPrank(params.mgv.governance());
    params.mgv.activate(params.olKeyBaseQuote, 0, 1, 1);
    params.mgv.activate(params.olKeyBaseQuote.flipped(), 0, 1, 1);
    vm.stopPrank();

    CoreKandel kandel = params.kandelSeeder.sow({olKeyBaseQuote: params.olKeyBaseQuote, liquiditySharing: true});

    require(kandel.router() == params.expectedRouter, "Incorrect router address");
    require(kandel.admin() == address(this), "Incorrect admin");
    if (address(params.expectedRouter) == address(0)) {
      require(kandel.FUND_OWNER() == address(kandel), "Incorrect id");
    } else {
      require(kandel.FUND_OWNER() == kandel.admin(), "Incorrect id");
      // starting smoke test with 10 inbound on Kandel
      deal({to: address(kandel), token: params.olKeyBaseQuote.inbound_tkn, give: 10});

      vm.startPrank(address(kandel));
      // push should take 5 inbound (out of 10) from kandel and send it to router
      uint pushed = kandel.router().push(
        RL.createOrder({token: IERC20(params.olKeyBaseQuote.inbound_tkn), fundOwner: kandel.FUND_OWNER()}), 5
      );
      require(pushed == 5, "smoke test: push failed");
      // pull should take 1 outbound from router and send it to kandel
      uint pulled = kandel.router().pull(
        RL.createOrder({token: IERC20(params.olKeyBaseQuote.inbound_tkn), fundOwner: kandel.FUND_OWNER()}), 1, true
      );
      require(pulled == 1, "smoke test: pull failed");
      vm.stopPrank();
    }
  }
}
