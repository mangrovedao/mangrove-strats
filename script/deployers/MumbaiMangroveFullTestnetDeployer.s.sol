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
import {OLKey} from "mgv_src/core/MgvLib.sol";

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

  function toMweiOfMatic(uint price) internal view returns (uint) {
    return (price * 10 ** 12) / maticPrice;
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
    IERC20 dai = IERC20(fork.get("DAI"));
    IERC20 usdc = IERC20(fork.get("USDC"));
    IERC20 weth = IERC20(fork.get("WETH"));

    uint[] memory prices = priceOracle.getAssetsPrices(dynamic([address(dai), address(usdc), address(weth)]));
    maticPrice = priceOracle.getAssetPrice(fork.get("WMATIC"));

    // 1 token_i = (prices[i] / 10**8) USD
    // 1 USD = (10**8 / maticPrice) Matic
    // 1 token_i = (prices[i] * 10**12 / maticPrice) gwei of Matic
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140, // this overrides Mangrove's gasprice for the computation of market's density      
      reader: reader,
      //Stable/stable ticks should be as small as possible, so using tick spacing 1
      market: Market({tkn0: address(dai), tkn1: address(usdc), tickSpacing: 1}),
      tkn1_in_Mwei: toMweiOfMatic(prices[0]),
      tkn2_in_Mwei: toMweiOfMatic(prices[1]),
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
    // Using 1 bps tick size like popular CEX.
      market: Market({tkn0: address(weth), tkn1: address(dai), tickSpacing: 1}),
      tkn1_in_Mwei: toMweiOfMatic(prices[2]),
      tkn2_in_Mwei: toMweiOfMatic(prices[0]),
      fee: 0
    });
    // Using 1 bps tick size like popular CEX.
    uint wethUsdcTickSpacing = 1;
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
      market: Market({tkn0: address(weth), tkn1: address(usdc), tickSpacing: wethUsdcTickSpacing}),
      tkn1_in_Mwei: toMweiOfMatic(prices[2]),
      tkn2_in_Mwei: toMweiOfMatic(prices[1]),
      fee: 0
    });

    // Activate MangroveOrder on markets
    IERC20[] memory iercs = new IERC20[](3);
    iercs[0] = weth;
    iercs[1] = dai;
    iercs[2] = usdc;
    new ActivateMangroveOrder().innerRun({
      mgvOrder: mangroveOrder,
      iercs: iercs
    });

    // Deploy Kandel instance via KandelSeeder to get the Kandel contract verified
    new KandelSower().innerRun({
      kandelSeeder: seeder,
      olKeyBaseQuote: OLKey(address(weth), address(usdc), wethUsdcTickSpacing),
      sharing: false,
      onAave: false,
      registerNameOnFork: false,
      name: ""
    });

    // Deploy AaveKandel instance via AaveKandelSeeder to get the AaveKandel contract verified
    new KandelSower().innerRun({
      kandelSeeder: aaveSeeder,
      olKeyBaseQuote: OLKey(address(weth), address(usdc), wethUsdcTickSpacing),
      sharing: false,
      onAave: true,
      registerNameOnFork: false,
      name: ""
    });
  }
}
