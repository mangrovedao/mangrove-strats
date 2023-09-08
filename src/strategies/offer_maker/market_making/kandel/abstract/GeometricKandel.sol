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
  ///@notice the parameters for Geometric Kandel have been set.
  ///@param spread in amount of price slots to jump for posting dual offer
  ///@param logPriceOffset of price progression
  event SetGeometricParams(uint spread, uint logPriceOffset);

  ///@notice Geometric Kandel parameters
  ///@param gasprice the gasprice to use for offers
  ///@param gasreq the gasreq to use for offers
  ///@param logPriceOffset the offset between logPrice for two consecutive price points.
  ///@param spread in amount of price slots to jump for posting dual offer. Must be less than or equal to 8.
  ///@param pricePoints the number of price points for the Kandel instance.
  struct Params {
    uint16 gasprice;
    uint24 gasreq;
    uint24 logPriceOffset;
    uint8 spread;
    uint8 pricePoints;
  }

  ///@notice Storage of the parameters for the strat.
  Params public params;

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

    bool geometricChanged = false;

    if (oldParams.logPriceOffset != newParams.logPriceOffset) {
      require(int(uint(newParams.logPriceOffset)) <= MAX_LOG_PRICE - MIN_LOG_PRICE, "Kandel/invalidLogPriceOffset");
      params.logPriceOffset = newParams.logPriceOffset;
      geometricChanged = true;
    }
    if (oldParams.spread != newParams.spread) {
      require(newParams.spread > 0 && newParams.spread <= 8, "Kandel/invalidSpread");
      params.spread = newParams.spread;
      geometricChanged = true;
    }

    if (geometricChanged) {
      emit SetGeometricParams(newParams.spread, newParams.logPriceOffset);
    }

    if (newParams.gasprice != 0 && newParams.gasprice != oldParams.gasprice) {
      setGasprice(newParams.gasprice);
    }

    if (newParams.gasreq != 0 && newParams.gasreq != oldParams.gasreq) {
      setGasreq(newParams.gasreq);
    }
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different logPriceOffset, pricePoints, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint firstAskIndex,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) external payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkInternal(distribution, firstAskIndex);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@dev internal version does not check onlyAdmin
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  function populateChunkInternal(Distribution calldata distribution, uint firstAskIndex) internal {
    populateChunk(distribution, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple transactions are needed to split initialization due to gas cost.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  function populateChunk(Distribution calldata distribution, uint firstAskIndex) external onlyAdmin {
    populateChunk(distribution, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice calculates the wants and gives for the dual offer according to the geometric price distribution.
  ///@param baDual the dual offer type.
  ///@param dualOfferGives the dual offer's current gives (can be 0)
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@param memoryParams the Kandel params (possibly with modified spread due to boundary condition)
  ///@return logPrice the log price for the dual offer
  ///@return gives the new gives for the dual offer
  ///@dev Define the (maker) price of the order as `p_order` with the log price of the order being `l_order := order.offer.logPrice()`
  /// the (maker) price of the dual order must be `p_dual := p_order / ratio^spread` which with the `logPriceOffset` defining the ratio means the log price of the dual
  /// becomes `l_dual := -(l_order - logPriceOffset*spread)` at which one should buy back at least what was sold.
  /// Now, since we do maximal compounding, maker wants to give all what taker gave. That is `max_offer_gives := order.gives`
  /// which we use in the code below where we also account for existing gives of the dual offer.
  function dualWantsGivesOfOffer(
    OfferType baDual,
    uint dualOfferGives,
    MgvLib.SingleOrder calldata order,
    Params memory memoryParams
  ) internal pure returns (int logPrice, uint gives) {
    uint spread = uint(memoryParams.spread);
    // order.gives:96
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
    logPrice = -(order.offer.logPrice() - int(uint(memoryParams.logPriceOffset)) * int(spread));
  }

  ///@notice returns the destination index to transport received liquidity to - a better (for Kandel) price index for the offer type.
  ///@param ba the offer type to transport to
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  ///@param pricePoints the number of price points
  ///@return better destination index
  ///@return spread the size of the price jump, which is `step` if the index boundaries were not reached
  function transportDestination(OfferType ba, uint index, uint step, uint pricePoints)
    internal
    pure
    returns (uint better, uint8 spread)
  {
    if (ba == OfferType.Ask) {
      better = index + step;
      if (better >= pricePoints) {
        better = pricePoints - 1;
        spread = uint8(better - index);
      } else {
        spread = uint8(step);
      }
    } else {
      if (index >= step) {
        better = index - step;
        spread = uint8(step);
      } else {
        // else better = 0
        spread = uint8(index - better);
      }
    }
  }

  ///@inheritdoc CoreKandel
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OfferType baDual, uint dualOfferId, uint dualIndex, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;
    baDual = dual(ba);

    // because of boundaries, actual spread might be lower than the one loaded in memoryParams
    // this would result populating a price index at a wrong price (too high for an Ask and too low for a Bid)
    (dualIndex, memoryParams.spread) =
      transportDestination(baDual, index, memoryParams.spread, memoryParams.pricePoints);

    dualOfferId = offerIdOfIndex(baDual, dualIndex);
    args.olKey = offerListOfOfferType(baDual);
    MgvStructs.OfferPacked dualOffer = MGV.offers(args.olKey, dualOfferId);

    (args.logPrice, args.gives) = dualWantsGivesOfOffer(baDual, dualOffer.gives(), order, memoryParams);

    // args.fund = 0; the offers are already provisioned
    // posthook should not fail if unable to post offers, we capture the error as incidents
    args.noRevert = true;
    args.gasprice = memoryParams.gasprice;
    args.gasreq = memoryParams.gasreq;
  }
}
