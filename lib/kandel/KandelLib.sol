// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {CoreKandel, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

library KandelLib {
  // Copied from DirectWithBidsAndAskDistribution.sol
  function transportDestination(OfferType ba, uint index, uint step, uint pricePoints)
    internal
    pure
    returns (uint better)
  {
    if (ba == OfferType.Ask) {
      better = index + step;
      if (better >= pricePoints) {
        better = pricePoints - 1;
      }
    } else {
      if (index >= step) {
        better = index - step;
      }
      // else better = 0
    }
  }


  function getPrices(uint initBase, uint initQuote, uint ratio, uint precision, uint pricePoints, uint pricePrecision)
    internal
    pure
    returns (uint[] memory prices)
  {
    prices = new uint[](pricePoints);
    uint initPrice = (initQuote * pricePrecision) / initBase;
    for (uint i = 0; i < pricePoints; ++i) {
      prices[i] = initPrice;
      initPrice = (initPrice * uint(ratio)) / (10 ** precision);
    }
  }

  function calculateDistribution(uint from, uint to, uint initBase, uint initQuote, uint ratio, uint precision, uint spread, uint firstAskIndex, uint pricePrecision, uint pricePoints)
    internal
    pure
    returns (CoreKandel.Distribution memory vars)
  {
    vars.indices = new uint[](to-from);
    vars.dualPrices = new uint[](to-from);
    vars.prices = new uint[](to-from);
    vars.gives = new uint[](to-from);

    uint[] memory prices = getPrices(initBase, initQuote, ratio, precision, pricePoints, pricePrecision);

    uint i = 0;
    for (; from < to; ++from) {
      vars.indices[i] = from;
      vars.gives[i] = from < firstAskIndex ? (initBase * prices[from]) / pricePrecision : initBase;
      vars.prices[i] = prices[from];
      uint dualIndex = transportDestination(from < firstAskIndex ? OfferType.Ask : OfferType.Bid, from, spread, pricePoints);
      vars.dualPrices[i] = prices[dualIndex]; 
      ++i;
    }
    return vars;
  }

  /// @notice should be invoked as an rpc call or via snapshot-revert - populates and returns pivots and amounts.
  function estimatePivotsAndRequiredAmount(
    CoreKandel.Distribution memory distribution,
    GeometricKandel kandel,
    uint firstAskIndex,
    GeometricKandel.Params memory params,
    uint funds
  ) internal returns (uint[] memory pivotIds, uint baseAmountRequired, uint quoteAmountRequired) {
    pivotIds = new uint[](distribution.indices.length);
    kandel.setParams(params);
    kandel.MGV().fund{value: funds}(address(kandel));
    kandel.populateChunk(distribution, pivotIds, firstAskIndex);
    for (uint i = 0; i < pivotIds.length; ++i) {
      uint index = distribution.indices[i];
      OfferType ba = index < firstAskIndex ? OfferType.Bid : OfferType.Ask;
      MgvStructs.OfferPacked offer = kandel.getOffer(ba, index);
      pivotIds[i] = offer.next();
      if (ba == OfferType.Bid) {
        quoteAmountRequired += offer.gives();
      } else {
        baseAmountRequired += offer.gives();
      }
    }
  }
}
