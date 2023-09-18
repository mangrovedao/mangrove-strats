// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OLKey} from "mgv_src/MgvLib.sol";
import {Direct} from "mgv_strat_src/strategies/offer_maker/abstract/Direct.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {HasIndexedBidsAndAsks} from "./HasIndexedBidsAndAsks.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

///@title `Direct` strat with an indexed collection of bids and asks which can be populated according to a desired base and quote distribution for gives and wants.
abstract contract DirectWithBidsAndAsksDistribution is Direct, HasIndexedBidsAndAsks {
  bytes32 internal constant LOW_VOLUME = "Kandel/volumeTooLow";

  ///@notice logs the start of a call to populate
  ///@notice By emitting this, an indexer will be able to know that the following events are in the context of populate.
  event PopulateStart();
  ///@notice logs the end of a call to populate
  ///@notice By emitting this, an indexer will know that the previous PopulateStart event is over.
  event PopulateEnd();

  ///@notice logs the start of a call to retractOffers
  ///@notice By emitting this, an indexer will be able to know that the following events are in the context of retract.
  event RetractStart();
  ///@notice logs the end of a call to retractOffers
  ///@notice By emitting this, an indexer will know that the previous RetractStart event is over.
  event RetractEnd();

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param gasreq the gasreq to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, uint gasreq, address reserveId)
    Direct(mgv, NO_ROUTER, gasreq, reserveId)
    HasIndexedBidsAndAsks(mgv)
  {}

  ///@param indices the indices to populate, in ascending order
  ///@param logPriceDist the log price distribution for the indices (the log price of base per quote for bids and quote per base for asks)
  ///@param givesDist the distribution of gives for the indices (the `quote` for bids and the `base` for asks)
  struct Distribution {
    uint[] indices;
    int[] logPriceDist;
    uint[] givesDist;
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `logPriceDist` and `givesDist`.
  ///@param distribution the distribution of prices for gives of base and quote for indices.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param gasreq the amount of gas units that are required to execute the trade.
  ///@param gasprice the gasprice used to compute offer's provision.
  ///@param bookDual whether to book the dual offer's id on Mangrove (should not be set when changing a single offer, e.g., to heal, and when known that dual is booked).
  ///@dev Invariant: After invoking this function an offer and its dual will be booked (unless `bookDual` is false).
  ///Gives of 0 means retract offer (but update price, gasreq, gasprice of the offer)
  function populateChunk(
    Distribution memory distribution,
    uint firstAskIndex,
    uint gasreq,
    uint gasprice,
    bool bookDual
  ) internal {
    emit PopulateStart();
    uint[] memory indices = distribution.indices;
    int[] memory logPriceDist = distribution.logPriceDist;
    uint[] memory givesDist = distribution.givesDist;

    uint i;

    OfferArgs memory args;
    // args.fund = 0; offers are already funded
    // args.noRevert = false; we want revert in case of failure

    args.olKey = offerListOfOfferType(OfferType.Bid);
    args.gasreq = gasreq;
    args.gasprice = gasprice;

    OfferArgs memory argsDual;
    // argsDual.fund = 0; offers are already funded
    // argsDual.noRevert = false; we want revert in case of failure
    // argsDual.gives = 0; // only reserve offer id.

    argsDual.olKey = args.olKey.flipped();
    argsDual.gasreq = gasreq;
    argsDual.gasprice = gasprice;

    // Minimum gives for offers (to post and retract)
    uint minGivesBid;
    uint minGivesAsk;
    {
      MgvStructs.LocalPacked local = MGV.local(argsDual.olKey);
      minGivesBid = local.density().multiplyUp(gasreq + local.offer_gasbase());
    }
    {
      MgvStructs.LocalPacked local = MGV.local(args.olKey);
      minGivesAsk = local.density().multiplyUp(gasreq + local.offer_gasbase());
    }

    for (; i < indices.length; ++i) {
      uint index = indices[i];
      if (index >= firstAskIndex) {
        break;
      }
      args.logPrice = logPriceDist[i];
      args.gives = givesDist[i];

      populateIndex(OfferType.Bid, offerIdOfIndex(OfferType.Bid, index), index, args, minGivesBid);
      if (bookDual) {
        //FIXME: Consider duals not having exactly the inverse price.
        argsDual.logPrice = -args.logPrice;
        populateIndex(OfferType.Ask, offerIdOfIndex(OfferType.Ask, index), index, argsDual, minGivesAsk);
      }
    }

    (args.olKey, argsDual.olKey) = (argsDual.olKey, args.olKey);

    for (; i < indices.length; ++i) {
      uint index = indices[i];
      args.logPrice = logPriceDist[i];
      args.gives = givesDist[i];

      populateIndex(OfferType.Ask, offerIdOfIndex(OfferType.Ask, index), index, args, minGivesAsk);
      if (bookDual) {
        argsDual.logPrice = -args.logPrice;
        populateIndex(OfferType.Bid, offerIdOfIndex(OfferType.Bid, index), index, argsDual, minGivesBid);
      }
    }
    emit PopulateEnd();
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index.
  ///@param ba whether the offer is a bid or an ask.
  ///@param offerId the Mangrove offer id (0 for a new offer).
  ///@param index the price index.
  ///@param args the argument of the offer.
  ///@param minGives the minimum gives to satisfy density requirement - used for reserving offerIds.
  ///@return result the result from Mangrove or Direct (an error if `args.noRevert` is `true`).
  function populateIndex(OfferType ba, uint offerId, uint index, OfferArgs memory args, uint minGives)
    internal
    returns (bytes32 result)
  {
    // if offer does not exist on mangrove yet
    if (offerId == 0) {
      // and offer should exist
      if (args.gives > 0) {
        // create it - we revert in case of failure (see populateChunk), so offerId is always > 0
        (offerId, result) = _newOffer(args);
        setIndexMapping(ba, index, offerId);
      } else {
        // else offerId && gives are 0 and the offer is posted and retracted to reserve the offerId
        args.gives = minGives;
        (offerId, result) = _newOffer(args);
        args.gives = 0;
        _retractOffer(args.olKey, offerId, false);
        setIndexMapping(ba, index, offerId);
        result = LOW_VOLUME;
      }
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0) {
        // * `gives == 0` may happen from populate in case of re-population where the offers in the spread are then retracted by setting gives to 0.
        // Update offer to set correct price, gasreq, gasprice, then retract
        args.gives = minGives;
        _updateOffer(args, offerId);
        args.gives = 0;
        _retractOffer(args.olKey, offerId, false);
        result = LOW_VOLUME;
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume and price
        result = _updateOffer(args, offerId);
      }
    }
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`.
  ///@param from the start index.
  ///@param to the end index.
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs.
  function retractOffers(uint from, uint to) public onlyAdmin {
    emit RetractStart();
    OLKey memory olKeyAsk = offerListOfOfferType(OfferType.Ask);
    OLKey memory olKeyBid = olKeyAsk.flipped();
    for (uint index = from; index < to; ++index) {
      // These offerIds could be recycled in a new populate
      uint offerId = offerIdOfIndex(OfferType.Ask, index);
      if (offerId != 0) {
        _retractOffer(olKeyAsk, offerId, true);
      }
      offerId = offerIdOfIndex(OfferType.Bid, index);
      if (offerId != 0) {
        _retractOffer(olKeyBid, offerId, true);
      }
    }
    emit RetractEnd();
  }
}
