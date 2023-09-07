// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {ActivateMarket, IERC20} from "mgv_script/core/ActivateMarket.s.sol";
import {
  ActivateMangroveOrder, MangroveOrder
} from "mgv_strat_script/strategies/mangroveOrder/ActivateMangroveOrder.s.sol";

import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader, Market} from "mgv_src/periphery/MgvReader.sol";

import {console} from "forge-std/console.sol";

/**
 * This scripts:
 * 1. activates the (TOKEN0, TOKEN1) market on matic(mum) using a gasprice of 140 gwei to compute density
 * 2. updates the reader to be aware of the opened market
 * 3. activates MangroveOrder for both TOKEN0 and TOKEN1
 *
 * TOKEN0 the name of the first token
 * TOKEN1 the name of the second token
 * MATIC_IN_USD the price of a matic in USD with fixed decimals precision (say n)
 * TOKEN[0/1]_IN_USD the price of token[0/1] in USD with the n decimals precision
 *
 * usage (with n=8):
 *  MATIC_IN_USD=$(cast ff 8 0.9)\
 *  TOKEN0=USDT \
 *  TOKEN1=WMATIC \
 *  TOKEN0_IN_USD=$(cast ff 8 1) \
 *  TOKEN1_IN_USD=$(cast ff 8 0.9) \
 *  forge script --fork-url mumbai MumbaiActivateMarket
 */

contract MumbaiActivateMarket is Deployer {
  uint maticPrice;

  function run() public {
    maticPrice = vm.envUint("MATIC_IN_USD");
    address token0 = envAddressOrName("TOKEN0");
    address token1 = envAddressOrName("TOKEN1");
    uint tickScale = vm.envUint("TICK_SCALE");
    uint price0 = vm.envUint("TOKEN0_IN_USD");
    uint price1 = vm.envUint("TOKEN1_IN_USD");
    Market memory market = Market({tkn0: token0, tkn1: token1, tickScale: tickScale});
    activateMarket(market, price0, price1);
    outputDeployment();
    smokeTest(market);
  }

  function toGweiOfMatic(uint price) internal view returns (uint) {
    return (price * 10 ** 9) / maticPrice;
  }

  function activateMarket(Market memory market, uint price0, uint price1) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    MgvReader reader = MgvReader(fork.get("MgvReader"));
    MangroveOrder mangroveOrder = MangroveOrder(fork.get("MangroveOrder"));

    // 1 token_i = (prices[i] / 10**8) USD
    // 1 USD = (10**8 / maticPrice) Matic
    // 1 token_i = (prices[i] * 10**9 / maticPrice) gwei of Matic
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140, // this overrides Mangrove's gasprice for the computation of market's density
      reader: reader,
      market: market,
      tkn1_in_gwei: toGweiOfMatic(price0),
      tkn2_in_gwei: toGweiOfMatic(price1),
      fee: 0
    });

    new ActivateMangroveOrder().innerRun({
      mgvOrder: mangroveOrder,
      iercs: dynamic([IERC20(market.tkn0), IERC20(market.tkn1)])
    });
  }

  function smokeTest(Market memory market) internal view {
    MgvReader reader = MgvReader(fork.get("MgvReader"));
    require(reader.isMarketOpen(market), "Smoke test failed");
  }
}
