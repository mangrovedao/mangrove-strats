// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";

import {IMangrove, KandelSeeder} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {
  AaveKandelSeeder,
  IPoolAddressesProvider
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {ERC4626KandelSeeder} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626KandelSeeder.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {KandelSeederDeployer, IERC20} from "./KandelSeederDeployer.s.sol";

contract PolygonKandelSeederDeployer is Deployer {
  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams()
    public
    returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder, ERC4626KandelSeeder erc4626Seeder)
  {
    // Create the DeploymentParams struct
    KandelSeederDeployer.DeploymentParams memory params = KandelSeederDeployer.DeploymentParams({
      mgv: IMangrove(fork.get("Mangrove")),
      addressesProvider: IPoolAddressesProvider(fork.get("AaveAddressProvider")),
      aaveKandelGasreq: 628_000,
      erc4626KandelGasreq: 628_000,
      kandelGasreq: 128_000,
      deployAaveKandel: true,
      deployERC4626Kandel: true,
      deployKandel: true,
      testBase: IERC20(fork.get("WETH.e")),
      testQuote: IERC20(fork.get("DAI.e"))
    });

    // Pass the struct to innerRun
    return new KandelSeederDeployer().innerRun(params);
  }
}
