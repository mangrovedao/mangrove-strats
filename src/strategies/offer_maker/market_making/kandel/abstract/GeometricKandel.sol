// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {CoreKandel} from "./CoreKandel.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";
import {MAX_LOG_PRICE, MIN_LOG_PRICE} from "mgv_lib/Constants.sol";

///@title Adds a geometric price progression to a `CoreKandel` strat without storing prices for individual price points.
abstract contract GeometricKandel is CoreKandel {
  ///@notice the base quote log price offset has been set.
  ///@param value the base quote log price offset used for the on-chain geometric progression deployment.
  event SetBaseQuoteLogPriceOffset(int value);

  ///@notice The log price offset used for the on-chain geometric progression deployment.
  int public baseQuoteLogPriceOffset;

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, uint gasprice, address reserveId)
    CoreKandel(mgv, olKeyBaseQuote, gasreq, gasprice, reserveId)
  {}

  ///@notice sets the log price offset if different from existing.
  ///@param _baseQuoteLogPriceOffset the new log price offset.
  function setBaseQuoteLogPriceOffset(int _baseQuoteLogPriceOffset) public onlyAdmin {
    require(int24(_baseQuoteLogPriceOffset) == _baseQuoteLogPriceOffset, "Kandel/logPriceOffsetTooHigh");
    if (baseQuoteLogPriceOffset != _baseQuoteLogPriceOffset) {
      baseQuoteLogPriceOffset = _baseQuoteLogPriceOffset;
      emit SetBaseQuoteLogPriceOffset(_baseQuoteLogPriceOffset);
    }
  }

  ///@notice publishes bids/asks for the gives distribution in the `givesDist` array.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param _baseQuoteLogPriceOffset the log price offset used for the geometric progression deployment.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param givesDist the distribution of gives for the indices (the `quote` for bids and the `base` for asks)
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  function populateFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    int _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint[] calldata givesDist,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) public payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkFromOffset(from, to, baseQuoteLogPriceIndex0, _baseQuoteLogPriceOffset, firstAskIndex, givesDist);
  }

  ///@notice publishes bids/asks for the gives distribution in the `givesDist` array.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param _baseQuoteLogPriceOffset the log price offset used for the geometric progression deployment.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param givesDist the distribution of gives for the indices (the `quote` for bids and the `base` for asks)
  ///@dev Index0 is lowest price offer (at a base/quote absolute price of baseQuoteLogPriceIndex0), and baseQuoteLogPriceOffset moves the price higher. Bids are posted at -logPrice since they are on the inverse offer list.
  function populateChunkFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    int _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint[] calldata givesDist
  ) public payable onlyAdmin {
    setBaseQuoteLogPriceOffset(_baseQuoteLogPriceOffset);
    uint count = to - from;
    Distribution memory distribution;
    distribution.indices = new uint[](count);
    distribution.logPriceDist = new int[](count);
    distribution.givesDist = givesDist;
    int baseQuoteLogPrice = (baseQuoteLogPriceIndex0 + baseQuoteLogPriceOffset * int(from));
    uint i = 0;
    for (uint index = from; index < firstAskIndex; ++index) {
      distribution.indices[i] = index;
      distribution.logPriceDist[i] = -baseQuoteLogPrice;
      baseQuoteLogPrice += baseQuoteLogPriceOffset;
      ++i;
    }

    for (uint index = firstAskIndex; index < to; ++index) {
      distribution.indices[i] = index;
      distribution.logPriceDist[i] = baseQuoteLogPrice;
      baseQuoteLogPrice += baseQuoteLogPriceOffset;
      ++i;
    }

    populateChunk(distribution, firstAskIndex, params.gasreq, params.gasprice, true);
  }
}
