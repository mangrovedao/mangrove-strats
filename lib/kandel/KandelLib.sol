// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {CoreKandel, OfferType} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {LogPriceLib} from "mgv_lib/LogPriceLib.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";

library KandelLib {
  function calculateDistribution(uint from, uint to, uint initBase, uint initQuote, uint logPriceOffset, uint firstAskIndex)
    internal
    pure
    returns (CoreKandel.Distribution memory vars, uint lastQuote)
  {
    vars.indices = new uint[](to-from);
    vars.logPriceDist = new int[](to-from);
    vars.givesDist = new uint[](to-from);
    vars.createDual = true;
    uint i = 0;
    for (; from < to; ++from) {
      vars.indices[i] = from;
      int logPrice = from < firstAskIndex ? LogPriceConversionLib.logPriceFromVolumes(initBase, initQuote) : LogPriceConversionLib.logPriceFromVolumes(initQuote, initBase);
      uint gives = from < firstAskIndex ? initQuote : initBase;
      vars.logPriceDist[i] = logPrice;
      vars.givesDist[i] = gives;
      // the logPriceOffset gives the price difference between two price points - the spread is involved when calculating the jump between a bid and its dual ask.
      initQuote = (initQuote * LogPriceLib.inboundFromOutbound(int(logPriceOffset), 1 ether)) / 1 ether;
      ++i;
    }
    return (vars, initQuote);
  }

  /// @notice should be invoked as an rpc call or via snapshot-revert - populates and returns amounts.
  function estimateRequiredAmount(
    CoreKandel.Distribution memory distribution,
    GeometricKandel kandel,
    uint firstAskIndex,
    GeometricKandel.Params memory params,
    uint funds
  ) internal returns (uint baseAmountRequired, uint quoteAmountRequired) {
    kandel.populate{value: funds}(distribution, firstAskIndex, params, 0, 0);
    for (uint i = 0; i < distribution.indices.length; ++i) {
      uint index = distribution.indices[i];
      OfferType ba = index < firstAskIndex ? OfferType.Bid : OfferType.Ask;
      MgvStructs.OfferPacked offer = kandel.getOffer(ba, index);
      if (ba == OfferType.Bid) {
        quoteAmountRequired += offer.gives();
      } else {
        baseAmountRequired += offer.gives();
      }
    }
  }
}
