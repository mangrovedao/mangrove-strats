// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {CoreKandel} from "./CoreKandel.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";
import {LogPriceLib} from "mgv_lib/LogPriceLib.sol";
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
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  function populateFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    int _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint bidGives,
    uint askGives,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) public payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkFromOffset(
      from, to, baseQuoteLogPriceIndex0, _baseQuoteLogPriceOffset, firstAskIndex, bidGives, askGives
    );
  }

  ///@notice publishes bids/asks for the distribution given by the parameters.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param _baseQuoteLogPriceOffset the log price offset used for the geometric progression deployment.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  ///@return distribution the distribution of offers.
  ///@dev the absolute price of an offer is the ratio of quote/base volumes of tokens it trades
  ///@dev the log price of offers on Mangrove are in relative taker price of maker's inbound/outbound volumes of tokens it trades
  ///@dev for Bids, outbound=quote, inbound=base so relative taker price of a a bid is the inverse of the absolute price.
  ///@dev for Asks, outbound=base, inbound=quote so relative taker price of an ask coincides with absolute price.
  ///@dev Index0 will contain the ask with the lowest relative price and the bid with the highest relative price. Absolute price is geometrically increasing over indexes.
  ///@dev logPriceOffset moves an offer relative price s.t. `AskLogPrice_{i+1} = AskLogPrice_i + logPriceOffset` and `BidLogPrice_{i+1} = BidLogPrice_i - logPriceOffset`
  function createDistribution(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    int _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint bidGives,
    uint askGives
  ) public pure returns (Distribution memory distribution) {
    require(bidGives != type(uint).max || askGives != type(uint).max, "Kandel/bothGivesVariable");
    uint count = to - from;
    distribution.indices = new uint[](count);
    distribution.logPriceDist = new int[](count);
    distribution.givesDist = new uint[](count);
    int baseQuoteLogPrice = (baseQuoteLogPriceIndex0 + _baseQuoteLogPriceOffset * int(from));
    uint i = 0;
    uint index = from;
    for (; index < firstAskIndex; ++index) {
      int logPrice = -baseQuoteLogPrice;
      distribution.indices[i] = index;
      distribution.logPriceDist[i] = logPrice;
      distribution.givesDist[i] =
        bidGives == type(uint).max ? LogPriceLib.outboundFromInbound(logPrice, askGives) : bidGives;
      baseQuoteLogPrice += _baseQuoteLogPriceOffset;
      ++i;
    }

    for (; index < to; ++index) {
      distribution.indices[i] = index;
      distribution.logPriceDist[i] = baseQuoteLogPrice;
      distribution.givesDist[i] =
        askGives == type(uint).max ? LogPriceLib.outboundFromInbound(baseQuoteLogPrice, bidGives) : askGives;
      baseQuoteLogPrice += _baseQuoteLogPriceOffset;
      ++i;
    }

    return distribution;
  }

  ///@notice publishes bids/asks for the distribution given by the parameters.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param _baseQuoteLogPriceOffset the log price offset used for the geometric progression deployment.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  function populateChunkFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    int _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint bidGives,
    uint askGives
  ) public payable onlyAdmin {
    setBaseQuoteLogPriceOffset(_baseQuoteLogPriceOffset);

    populateChunk(
      createDistribution(from, to, baseQuoteLogPriceIndex0, _baseQuoteLogPriceOffset, firstAskIndex, bidGives, askGives),
      firstAskIndex,
      params.gasreq,
      params.gasprice,
      true
    );
  }
}
