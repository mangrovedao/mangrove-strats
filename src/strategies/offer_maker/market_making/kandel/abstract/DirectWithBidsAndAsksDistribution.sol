// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OLKey} from "mgv_src/MgvLib.sol";
import {Direct} from "mgv_strat_src/strategies/offer_maker/abstract/Direct.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {HasIndexedBidsAndAsks} from "./HasIndexedBidsAndAsks.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

///@title `Direct` strat with an indexed collection of bids and asks which can be populated according to a desired base and quote distribution for gives and wants.
abstract contract DirectWithBidsAndAsksDistribution is Direct, HasIndexedBidsAndAsks {
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

  ///@notice Publishes bids/asks for the distribution in the `indices`. Care must be taken to publish offers in meaningful chunks. For instance, for Kandel an offer and its dual should be published in the same chunk (one being optionally initially dead).
  ///@param bidDistribution the distribution of prices for gives of quote for indices.
  ///@param askDistribution the distribution of prices for gives of base for indices.
  ///@param gasreq the amount of gas units that are required to execute the trade.
  ///@param gasprice the gasprice used to compute offer's provision.
  ///@dev Gives of 0 means create/update and then retract offer (but update price, gasreq, gasprice of the offer)
  function populateChunk(
    Distribution memory bidDistribution,
    Distribution memory askDistribution,
    uint gasreq,
    uint gasprice
  ) internal {
    emit PopulateStart();
    // Initialize static values of args
    OfferArgs memory args;
    // args.fund = 0; offers are already funded
    // args.noRevert = false; we want revert in case of failure
    args.gasreq = gasreq;
    args.gasprice = gasprice;

    // Populate bids
    uint[] memory indices = bidDistribution.indices;
    int[] memory logPriceDist = bidDistribution.logPriceDist;
    uint[] memory givesDist = bidDistribution.givesDist;
    args.olKey = offerListOfOfferType(OfferType.Bid);

    // Minimum gives for offers (to post and retract)
    uint minGives;
    MgvStructs.LocalPacked local = MGV.local(args.olKey);
    minGives = local.density().multiplyUp(gasreq + local.offer_gasbase());
    for (uint i; i < indices.length; ++i) {
      uint index = indices[i];
      args.logPrice = logPriceDist[i];
      args.gives = givesDist[i];
      populateIndex(OfferType.Bid, offerIdOfIndex(OfferType.Bid, index), index, args, minGives);
    }

    // Populate asks
    indices = askDistribution.indices;
    logPriceDist = askDistribution.logPriceDist;
    givesDist = askDistribution.givesDist;
    args.olKey = args.olKey.flipped();

    local = MGV.local(args.olKey);
    minGives = local.density().multiplyUp(gasreq + local.offer_gasbase());
    for (uint i; i < indices.length; ++i) {
      uint index = indices[i];
      args.logPrice = logPriceDist[i];
      args.gives = givesDist[i];
      populateIndex(OfferType.Ask, offerIdOfIndex(OfferType.Ask, index), index, args, minGives);
    }
    emit PopulateEnd();
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index.
  ///@param ba whether the offer is a bid or an ask.
  ///@param offerId the Mangrove offer id (0 for a new offer).
  ///@param index the price index.
  ///@param args the argument of the offer. `args.gives=0` means offer will be created/updated and then retracted.
  ///@param minGives the minimum gives to satisfy density requirement - used for creating/updating offers when args.gives=0.
  function populateIndex(OfferType ba, uint offerId, uint index, OfferArgs memory args, uint minGives) internal {
    // if offer does not exist on mangrove yet
    if (offerId == 0) {
      // and offer should be live
      if (args.gives > 0) {
        // create it - we revert in case of failure (see populateChunk), so offerId is always > 0
        (offerId,) = _newOffer(args);
        setIndexMapping(ba, index, offerId);
      } else {
        // else offerId && gives are 0 and the offer is posted and retracted to reserve the offerId and set the price
        // set args.gives to minGives to be above density requirement, we do it here since we use the args.gives=0 to signal a dead offer.
        args.gives = minGives;
        // create it - we revert in case of failure (see populateChunk), so offerId is always > 0
        (offerId,) = _newOffer(args);
        // reset args.gives since args is reused
        args.gives = 0;
        // retract, keeping provision, thus the offer is reserved and ready for use in posthook.
        _retractOffer(args.olKey, offerId, false);
        setIndexMapping(ba, index, offerId);
      }
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0) {
        // * `gives == 0` may happen from populate in case of re-population where some offers are then retracted by setting gives to 0.
        // set args.gives to minGives to be above density requirement, we do it here since we use the args.gives=0 to signal a dead offer.
        args.gives = minGives;
        // Update offer to set correct price, gasreq, gasprice, then retract
        _updateOffer(args, offerId);
        // reset args.gives since args is reused
        args.gives = 0;
        // retract, keeping provision, thus the offer is reserved and ready for use in posthook.
        _retractOffer(args.olKey, offerId, false);
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume and price
        _updateOffer(args, offerId);
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
