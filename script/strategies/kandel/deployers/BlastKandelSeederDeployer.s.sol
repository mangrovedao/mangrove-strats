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
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {CoreKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {BlastKandelSeeder} from "@mgv-strats/src/strategies/chains/blast/kandel/BlastKandelSeeder.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";
import {BlastKandel} from "@mgv-strats/src/strategies/chains/blast/kandel/BlastKandel.sol";

/**
 * @notice deploys a Kandel seeder
 */
contract BlastKandelSeederDeployer is Deployer, Test2 {
  function run() public {
    bool deployKandel = true;
    try vm.envBool("DEPLOY_KANDEL") returns (bool deployKandel_) {
      deployKandel = deployKandel_;
    } catch {}
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      kandelGasreq: 128_000,
      deployKandel: deployKandel,
      testBase: IERC20(envAddressOrName("TEST_BASE")),
      testQuote: IERC20(envAddressOrName("TEST_QUOTE")),
      blastContract: IBlast(envAddressOrName("BLAST_CONTRACT", "Blast")),
      blastGovernor: envAddressOrName("BLAST_GOVERNOR", "BlastGovernor"),
      blastPointsContract: IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints")),
      blastPointsOperator: envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator")
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    uint kandelGasreq,
    bool deployKandel,
    IERC20 testBase,
    IERC20 testQuote,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) public returns (BlastKandelSeeder seeder) {
    // Tick spacing is irrelevant, only used to deploy for verification and to use as a library
    uint tickSpacing = 1;
    OLKey memory olKeyBaseQuote = OLKey(address(testBase), address(testQuote), tickSpacing);

    if (deployKandel) {
      prettyLog("Deploying Kandel seeder...");
      broadcast();
      seeder =
        new BlastKandelSeeder(mgv, kandelGasreq, blastContract, blastGovernor, blastPointsContract, blastPointsOperator);
      fork.set("KandelSeeder", address(seeder));

      console.log("Deploying Kandel instance for code verification and to use as proxy for KandelLib...");
      broadcast();
      BlastKandel kandel =
        new BlastKandel(mgv, olKeyBaseQuote, 1, blastContract, blastGovernor, blastPointsContract, blastPointsOperator);
      // Write the kandel's address so it can be used as a library to call createGeometricDistribution
      fork.set("KandelLib", address(kandel));
      smokeTest(mgv, olKeyBaseQuote, seeder, AbstractRouter(address(0)));
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
        RL.createOrder({token: IERC20(olKeyBaseQuote.inbound_tkn), fundOwner: kandel.FUND_OWNER()}), 5
      );
      require(pushed == 5, "smoke test: push failed");
      // pull should take 1 outbound from router and send it to kandel
      uint pulled = kandel.router().pull(
        RL.createOrder({token: IERC20(olKeyBaseQuote.inbound_tkn), fundOwner: kandel.FUND_OWNER()}), 1, true
      );
      require(pulled == 1, "smoke test: pull failed");
      vm.stopPrank();
    }
  }
}
