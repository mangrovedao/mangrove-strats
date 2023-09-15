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
  //TODO move to AbstractKandel? Reconsider limits
  ///@notice the spread has been set.
  ///@param value the spread in amount of price slots to jump for posting dual offer
  event SetSpread(uint value);

  ///@notice the base quote log price offset has been set.
  ///@param value the base quote log price offset used for the on-chain geometric progression deployment.
  event SetBaseQuoteLogPriceOffset(int value);

  ///@notice Geometric Kandel parameters
  ///@param gasprice the gasprice to use for offers
  ///@param gasreq the gasreq to use for offers
  ///@param spread in amount of price slots to jump for posting dual offer. Must be less than or equal to 8.
  ///@param pricePoints the number of price points for the Kandel instance.
  struct Params {
    uint16 gasprice;
    uint24 gasreq;
    uint8 spread;
    uint8 pricePoints;
  }

  ///@notice Storage of the parameters for the strat.
  Params public params;

  ///@notice The log price offset used for the on-chain geometric progression deployment.
  int public baseQuoteLogPriceOffset;

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, uint gasprice, address reserveId)
    CoreKandel(mgv, olKeyBaseQuote, gasreq, reserveId)
  {
    setGasprice(gasprice);
  }

  ///@notice sets the spread
  ///@param spread the spread.
  function setSpread(uint spread) public onlyAdmin {
    require(spread > 0 && spread <= 8, "Kandel/invalidSpread");
    params.spread = uint8(spread);
    emit SetSpread(spread);
  }

  /// @inheritdoc AbstractKandel
  function setGasprice(uint gasprice) public override onlyAdmin {
    uint16 gasprice_ = uint16(gasprice);
    require(gasprice_ == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = gasprice_;
    emit SetGasprice(gasprice_);
  }

  /// @inheritdoc AbstractKandel
  function setGasreq(uint gasreq) public override onlyAdmin {
    uint24 gasreq_ = uint24(gasreq);
    require(gasreq_ == gasreq, "Kandel/gasreqTooHigh");
    params.gasreq = gasreq_;
    emit SetGasreq(gasreq_);
  }

  /// @notice Updates the params to new values.
  /// @param newParams the new params to set.
  function setParams(Params calldata newParams) internal {
    Params memory oldParams = params;

    if (oldParams.pricePoints != newParams.pricePoints) {
      setLength(newParams.pricePoints);
      params.pricePoints = newParams.pricePoints;
    }

    if (oldParams.spread != newParams.spread) {
      setSpread(newParams.spread);
    }

    if (newParams.gasprice != 0 && newParams.gasprice != oldParams.gasprice) {
      setGasprice(newParams.gasprice);
    }

    if (newParams.gasreq != 0 && newParams.gasreq != oldParams.gasreq) {
      setGasreq(newParams.gasreq);
    }
  }

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
    distribution.createDual = true;
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

    populateChunkInternal(distribution, firstAskIndex);
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `logPriceDist` and `givesDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different pricePoints or spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution memory distribution,
    uint firstAskIndex,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) public payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkInternal(distribution, firstAskIndex);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `logPriceDist` and `givesDist`.
  ///@dev internal version does not check onlyAdmin
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  function populateChunkInternal(Distribution memory distribution, uint firstAskIndex) internal {
    populateChunk(distribution, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `logPriceDist` and `givesDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple transactions are needed to split initialization due to gas cost.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  function populateChunk(Distribution calldata distribution, uint firstAskIndex) external onlyAdmin {
    populateChunk(distribution, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice calculates the gives for the dual offer.
  ///@param dualOfferGives the dual offer's current gives (can be 0)
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return gives the new gives for the dual offer
  function dualGivesOfOffer(uint dualOfferGives, MgvLib.SingleOrder calldata order) internal pure returns (uint gives) {
    // gives from order.gives:96
    gives = order.gives;

    // adding to gives what the offer was already giving so gives could be greater than 2**96
    // gives:97
    gives += dualOfferGives;
    if (uint96(gives) != gives) {
      // this should not be reached under normal circumstances unless strat is posting on top of an existing offer with an abnormal volume
      // to prevent gives to be too high, we let the surplus become "pending" (unpublished liquidity)
      gives = type(uint96).max;
    }
    //FIXME: can wants be too high or too low?
  }

  ///@notice returns the destination index to transport received liquidity to - a better (for Kandel) price index for the offer type.
  ///@param ba the offer type to transport to
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  ///@param pricePoints the number of price points
  ///@return better destination index
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

  ///@inheritdoc CoreKandel
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint dualOfferId, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;
    OfferType baDual = dual(ba);

    // because of boundaries, actual spread might be lower than the one loaded in memoryParams
    // this would result populating a price index at a wrong price (too high for an Ask and too low for a Bid)
    uint dualIndex = transportDestination(baDual, index, memoryParams.spread, memoryParams.pricePoints);

    dualOfferId = offerIdOfIndex(baDual, dualIndex);
    args.olKey = offerListOfOfferType(baDual);
    MgvStructs.OfferPacked dualOffer = MGV.offers(args.olKey, dualOfferId);

    args.gives = dualGivesOfOffer(dualOffer.gives(), order);
    args.logPrice = dualOffer.logPrice();

    // args.fund = 0; the offers are already provisioned
    // posthook should not fail if unable to post offers, we capture the error as incidents
    args.noRevert = true;
    args.gasprice = memoryParams.gasprice;
    args.gasreq = memoryParams.gasreq;
  }
}
