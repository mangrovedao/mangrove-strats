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
  ///@notice The log price offset for absolute price used for the on-chain geometric progression deployment in `createDistribution`.
  ///@param value the log price offset.
  event SetBaseQuoteLogPriceOffset(uint value);
  ///@notice By emitting this data, an indexer will be able to keep track of what the spread and logPriceOffset is for the Kandel instance.

  ///@notice The log price offset for absolute price used for the on-chain geometric progression deployment in `createDistribution`.
  uint public baseQuoteLogPriceOffset;

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
  function setBaseQuoteLogPriceOffset(uint _baseQuoteLogPriceOffset) public onlyAdmin {
    require(uint24(_baseQuoteLogPriceOffset) == _baseQuoteLogPriceOffset, "Kandel/logPriceOffsetTooHigh");
    if (baseQuoteLogPriceOffset != _baseQuoteLogPriceOffset) {
      baseQuoteLogPriceOffset = _baseQuoteLogPriceOffset;
      emit SetBaseQuoteLogPriceOffset(_baseQuoteLogPriceOffset);
    }
  }

  ///@notice Creates a distribution of bids and asks given by the parameters, while reading additional parameters from the Kandel instance. Dual offers are included with gives=0.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  ///@return bidDistribution the distribution of bids.
  ///@return askDistribution the distribution of asks.
  ///@dev See `createDistribution` overload for further details.
  function createDistribution(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    uint firstAskIndex,
    uint bidGives,
    uint askGives
  ) external view returns (Distribution memory bidDistribution, Distribution memory askDistribution) {
    Params memory parameters = params;
    return createDistribution(
      from,
      to,
      baseQuoteLogPriceIndex0,
      baseQuoteLogPriceOffset,
      firstAskIndex,
      bidGives,
      askGives,
      parameters.pricePoints,
      parameters.spread
    );
  }

  ///@notice Creates a distribution of bids and asks given by the parameters. Dual offers are included with gives=0.
  ///@param from populate offers starting from this index (inclusive). Must be at most `pricePoints`.
  ///@param to populate offers until this index (exclusive). Must be at most `pricePoints`.
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param _baseQuoteLogPriceOffset the log price offset used for the geometric progression deployment. Must be at least 1.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask. Must be at most `pricePoints`.
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  ///@param spread in amount of price slots to jump for posting dual offer. Must be less than `pricePoints`.
  ///@param pricePoints the number of price points for the Kandel instance. Must be at least 2.
  ///@return bidDistribution the distribution of bids.
  ///@return askDistribution the distribution of asks.
  ///@dev the absolute price of an offer is the ratio of quote/base volumes of tokens it trades
  ///@dev the log price of offers on Mangrove are in relative taker price of maker's inbound/outbound volumes of tokens it trades
  ///@dev for Bids, outbound=quote, inbound=base so relative taker price of a a bid is the inverse of the absolute price.
  ///@dev for Asks, outbound=base, inbound=quote so relative taker price of an ask coincides with absolute price.
  ///@dev Index0 will contain the ask with the lowest relative price and the bid with the highest relative price. Absolute price is geometrically increasing over indexes.
  ///@dev logPriceOffset moves an offer relative price s.t. `AskLogPrice_{i+1} = AskLogPrice_i + logPriceOffset` and `BidLogPrice_{i+1} = BidLogPrice_i - logPriceOffset`
  ///@dev A hole is left in the middle at the size of spread - either an offer or its dual is posted, not both.
  ///@dev The caller should make sure the minimum and maximum log price does not exceed the MIN_LOG_PRICE and MAX_LOG_PRICE from respectively; otherwise, populate will fail for those offers.
  function createDistribution(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    uint _baseQuoteLogPriceOffset,
    uint firstAskIndex,
    uint bidGives,
    uint askGives,
    uint pricePoints,
    uint spread
  ) public pure returns (Distribution memory bidDistribution, Distribution memory askDistribution) {
    require(bidGives != type(uint).max || askGives != type(uint).max, "Kandel/bothGivesVariable");

    // First we restrict boundaries of bids and asks.

    // Create live bids up till first ask, except stop where live asks will have a dual bid.
    uint bidBound;
    {
      // Rounding - we skip an extra live bid if spread is odd.
      uint bidHoleSize = spread / 2 + spread % 2;
      // If first ask is close to start, then there are no room for live bids.
      bidBound = firstAskIndex > bidHoleSize ? firstAskIndex - bidHoleSize : 0;
      // If spread is large there is not enough room for dual outside
      uint lastBidWithPossibleDualAsk = pricePoints - spread;
      if (bidBound > lastBidWithPossibleDualAsk) {
        bidBound = lastBidWithPossibleDualAsk;
      }
    }
    // Here firstAskIndex becomes the index of the first actual ask, and not just the boundary - we need to take spread and from into account.
    firstAskIndex = firstAskIndex + spread / 2;
    // We should not place live asks near the beginning, there needs to be room for the dual bid.
    if (firstAskIndex < spread) {
      firstAskIndex = spread;
    }

    // Finally, account for the from/to boundaries
    if (to < bidBound) {
      bidBound = to;
    }
    if (firstAskIndex < from) {
      firstAskIndex = from;
    }

    // Allocate distributions - there should be room for live bids and asks, and their duals.
    {
      uint count = (from < bidBound ? bidBound - from : 0) + (firstAskIndex < to ? to - firstAskIndex : 0);
      bidDistribution.indices = new uint[](count);
      bidDistribution.logPriceDist = new int[](count);
      bidDistribution.givesDist = new uint[](count);
      askDistribution.indices = new uint[](count);
      askDistribution.logPriceDist = new int[](count);
      askDistribution.givesDist = new uint[](count);
    }

    // Start bids at from
    uint index = from;
    // Calculate the absolute log price of the first price point
    int baseQuoteLogPrice = (baseQuoteLogPriceIndex0 + int(_baseQuoteLogPriceOffset) * int(index));
    // A counter for insertion in the distribution structs
    uint i = 0;
    for (; index < bidBound; ++index) {
      // Add live bid
      int logPrice = -baseQuoteLogPrice;
      bidDistribution.indices[i] = index;
      bidDistribution.logPriceDist[i] = logPrice;
      // Use bidGives unless it should be derived from ask at the price
      bidDistribution.givesDist[i] =
        bidGives == type(uint).max ? LogPriceLib.outboundFromInbound(logPrice, askGives) : bidGives;

      // Add dual (dead) ask
      uint dualIndex = transportDestination(OfferType.Ask, index, spread, pricePoints);
      askDistribution.indices[i] = dualIndex;
      askDistribution.logPriceDist[i] = (baseQuoteLogPriceIndex0 + int(_baseQuoteLogPriceOffset) * int(dualIndex));
      //askDistribution.givesDist[i] = 0; // set to 0 by default

      // Next log price
      baseQuoteLogPrice += int(_baseQuoteLogPriceOffset);
      ++i;
    }

    // Start asks from (adjusted) firstAskIndex
    index = firstAskIndex;
    // Calculate the absolute log price of the first ask
    baseQuoteLogPrice = (baseQuoteLogPriceIndex0 + int(_baseQuoteLogPriceOffset) * int(index));
    for (; index < to; ++index) {
      // Add live ask
      askDistribution.indices[i] = index;
      askDistribution.logPriceDist[i] = baseQuoteLogPrice;
      // Use askGives unless it should be derived from bid at the price
      askDistribution.givesDist[i] =
        askGives == type(uint).max ? LogPriceLib.outboundFromInbound(baseQuoteLogPrice, bidGives) : askGives;
      // Add dual (dead) bid
      uint dualIndex = transportDestination(OfferType.Bid, index, spread, pricePoints);
      bidDistribution.indices[i] = dualIndex;
      bidDistribution.logPriceDist[i] = -(baseQuoteLogPriceIndex0 + int(_baseQuoteLogPriceOffset) * int(dualIndex));
      //bidDistribution.givesDist[i] = 0; // set to 0 by default

      // Next log price
      baseQuoteLogPrice += int(_baseQuoteLogPriceOffset);
      ++i;
    }

    return (bidDistribution, askDistribution);
  }

  ///@notice publishes bids/asks according to a geometric distribution, and sets all parameters according to inputs.
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
  ///@dev See `createDistribution` for further details.
  function populateFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    uint _baseQuoteLogPriceOffset,
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
    setBaseQuoteLogPriceOffset(_baseQuoteLogPriceOffset);

    depositFunds(baseAmount, quoteAmount);

    populateChunkFromOffset(from, to, baseQuoteLogPriceIndex0, firstAskIndex, bidGives, askGives);
  }

  ///@notice publishes bids/asks according to a geometric distribution, and reads parameters from the Kandel instance.
  ///@param from populate offers starting from this index (inclusive).
  ///@param to populate offers until this index (exclusive).
  ///@param baseQuoteLogPriceIndex0 the log price of base per quote for the price point at index 0.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param bidGives The initial amount of quote to give for all bids. If 0, only book the offer, if type(uint).max then askGives is used as base for bids, and the quote the bid gives is set to according to the price.
  ///@param askGives The initial amount of base to give for all asks. If 0, only book the offer, if type(uint).max then bidGives is used as quote for asks, and the base the ask gives is set to according to the price.
  ///@dev This is typically used after a call to `populateFromOffset` to populate the rest of the offers with the same parameters. See that function for further details.
  function populateChunkFromOffset(
    uint from,
    uint to,
    int baseQuoteLogPriceIndex0,
    uint firstAskIndex,
    uint bidGives,
    uint askGives
  ) public payable onlyAdmin {
    Params memory parameters = params;
    (Distribution memory bidDistribution, Distribution memory askDistribution) = createDistribution(
      from,
      to,
      baseQuoteLogPriceIndex0,
      baseQuoteLogPriceOffset,
      firstAskIndex,
      bidGives,
      askGives,
      parameters.pricePoints,
      parameters.spread
    );
    populateChunk(bidDistribution, askDistribution, parameters.gasreq, parameters.gasprice);
  }
}
