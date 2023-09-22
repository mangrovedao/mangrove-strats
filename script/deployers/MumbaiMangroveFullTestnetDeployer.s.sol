// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {MumbaiMangroveDeployer} from "mgv_script/core/deployers/MumbaiMangroveDeployer.s.sol";
import {MumbaiMangroveOrderDeployer} from
  "mgv_strat_script/strategies/mangroveOrder/deployers/MumbaiMangroveOrderDeployer.s.sol";
import {
  MumbaiKandelSeederDeployer,
  KandelSeeder,
  AaveKandelSeeder
} from "mgv_strat_script/strategies/kandel/deployers/MumbaiKandelSeederDeployer.s.sol";

import {Market, ActivateMarket, IERC20} from "mgv_script/core/ActivateMarket.s.sol";
import {
  ActivateMangroveOrder, MangroveOrder
} from "mgv_strat_script/strategies/mangroveOrder/ActivateMangroveOrder.s.sol";
import {KandelSower, IMangrove} from "mgv_strat_script/strategies/kandel/KandelSower.s.sol";
import {IPoolAddressesProvider} from "mgv_strat_src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "mgv_strat_src/strategies/vendor/aave/v3/IPriceOracleGetter.sol";

import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

import {console} from "forge-std/console.sol";

/**
 * Deploy and configure a complete Mangrove testnet deployment:
 * - Mangrove and periphery contracts
 * - MangroveOrder
 * - KandelSeeder and AaveKandelSeeder
 * - open markets: DAI/USDC, WETH/DAI, WETH/USDC
 * - prices given by the oracle are in USD with 8 decimals of precision.
 *      Script will throw if oracle uses ETH as base currency instead of USD (as oracle contract permits).
 */
contract MumbaiMangroveFullTestnetDeployer is Deployer {
  uint internal maticPrice;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function toGweiOfMatic(uint price) internal view returns (uint) {
    return (price * 10 ** 9) / maticPrice;
  }

  function runWithChainSpecificParams() public {
    // Deploy Mangrove
    new MumbaiMangroveDeployer().runWithChainSpecificParams();
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    MgvReader reader = MgvReader(fork.get("MgvReader"));
    IPriceOracleGetter priceOracle =
      IPriceOracleGetter(IPoolAddressesProvider(fork.get("Aave")).getAddress("PRICE_ORACLE"));
    require(priceOracle.BASE_CURRENCY() == address(0), "script assumes base currency is in USD");

    // Deploy MangroveOrder
    new MumbaiMangroveOrderDeployer().runWithChainSpecificParams();
    MangroveOrder mangroveOrder = MangroveOrder(fork.get("MangroveOrder"));

    // Deploy KandelSeeder & AaveKandelSeeder
    (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) = new MumbaiKandelSeederDeployer().runWithChainSpecificParams();

    // Activate markets
    address dai = fork.get("DAI");
    address usdc = fork.get("USDC");
    address weth = fork.get("WETH");

    uint[] memory prices = priceOracle.getAssetsPrices(dynamic([dai, usdc, weth]));
    maticPrice = priceOracle.getAssetPrice(fork.get("WMATIC"));

    // 1 token_i = (prices[i] / 10**8) USD
    // 1 USD = (10**8 / maticPrice) Matic
    // 1 token_i = (prices[i] * 10**9 / maticPrice) gwei of Matic
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140, // this overrides Mangrove's gasprice for the computation of market's density
      reader: reader,
      //FIXME: what tick scale?
      market: Market({tkn0: dai, tkn1: usdc, tickScale: 1}),
      tkn1_in_gwei: toGweiOfMatic(prices[0]),
      tkn2_in_gwei: toGweiOfMatic(prices[1]),
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
      //FIXME: what tick scale?
      market: Market({tkn0: weth, tkn1: dai, tickScale: 1}),
      tkn1_in_gwei: toGweiOfMatic(prices[2]),
      tkn2_in_gwei: toGweiOfMatic(prices[0]),
      fee: 0
    });
    //FIXME: what tick scale?
    uint wethUsdcTickScale = 1;
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
      market: Market({tkn0: weth, tkn1: usdc, tickScale: wethUsdcTickScale}),
      tkn1_in_gwei: toGweiOfMatic(prices[2]),
      tkn2_in_gwei: toGweiOfMatic(prices[1]),
      fee: 0
    });

    // Activate MangroveOrder on markets
    IERC20[] memory iercs = new IERC20[](3);
    iercs[0] = IERC20(weth);
    iercs[1] = IERC20(dai);
    iercs[2] = IERC20(usdc);
    new ActivateMangroveOrder().innerRun({
      mgvOrder: mangroveOrder,
      iercs: iercs
    });

    // Deploy Kandel instance via KandelSeeder to get the Kandel contract verified
    new KandelSower().innerRun({
      kandelSeeder: seeder,
      olKeyBaseQuote: OLKey(weth, usdc, wethUsdcTickScale),
      sharing: false,
      onAave: false,
      registerNameOnFork: false,
      name: ""
    });

    // Deploy AaveKandel instance via AaveKandelSeeder to get the AaveKandel contract verified
    new KandelSower().innerRun({
      kandelSeeder: aaveSeeder,
      olKeyBaseQuote: OLKey(weth, usdc, wethUsdcTickScale),
      sharing: false,
      onAave: true,
      registerNameOnFork: false,
      name: ""
    });
  }
}
