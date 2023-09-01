// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {OfferType} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {toFixed} from "mgv_lib/Test2.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KandelStatus is Deployer {
  function run() public view {
    innerRun({kdl: GeometricKandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(GeometricKandel kdl) public view {
    IERC20 base = kdl.BASE();
    IERC20 quote = kdl.QUOTE();
    uint baseDecimals = base.decimals();
    uint quoteDecimals = quote.decimals();
    (,,,,,, uint8 pricePoints) = kdl.params();

    for (uint i; i < pricePoints; ++i) {
      MgvStructs.OfferPacked ask = kdl.getOffer(OfferType.Ask, i);
      MgvStructs.OfferPacked bid = kdl.getOffer(OfferType.Bid, i);

      if (ask.gives() > 0) {
        uint p = ask.wants() /*quote*/ * 10 ** baseDecimals / ask.gives(); /*base */
        console.log("ask @ %s for %s %s", toFixed(p, quoteDecimals), toFixed(ask.gives(), baseDecimals), base.symbol());
      }
      if (bid.gives() > 0) {
        uint p = bid.gives() /*quote*/ * 10 ** baseDecimals / bid.wants(); /*base */
        console.log(
          "bid @ %s for %s %s", toFixed(p, quoteDecimals), toFixed(bid.gives(), quoteDecimals), quote.symbol()
        );
      }
    }
    console.log(
      "{ pending base: %d, pending quote: %s",
      toFixed(uint(kdl.pending(OfferType.Ask)), baseDecimals),
      toFixed(uint(kdl.pending(OfferType.Bid)), quoteDecimals),
      "}"
    );
  }
}
