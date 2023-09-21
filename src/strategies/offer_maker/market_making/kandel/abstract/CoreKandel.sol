// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {DirectWithBidsAndAsksDistribution} from "./DirectWithBidsAndAsksDistribution.sol";
import {TradesBaseQuotePair} from "./TradesBaseQuotePair.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

///@title the core of Kandel strategies which creates or updates a dual offer whenever an offer is taken.
///@notice `CoreKandel` is agnostic to the chosen price distribution.
abstract contract CoreKandel is DirectWithBidsAndAsksDistribution, TradesBaseQuotePair, AbstractKandel {
  ///@notice Core Kandel parameters
  ///@param gasprice the gasprice to use for offers
  ///@param gasreq the gasreq to use for offers
  ///@param stepSize in amount of price points to jump for posting dual offer.
  ///@param pricePoints the number of price points for the Kandel instance.
  struct Params {
    uint16 gasprice;
    uint24 gasreq;
    uint104 stepSize;
    uint112 pricePoints;
  }

  ///@notice Storage of the parameters for the strat.
  Params public params;

  ///@notice sets the step size
  ///@param stepSize the step size.
  function setStepSize(uint stepSize) public onlyAdmin {
    uint104 stepSize_ = uint104(stepSize);
    require(stepSize > 0, "Kandel/stepSizeTooLow");
    require(stepSize_ == stepSize && stepSize < params.pricePoints, "Kandel/stepSizeTooHigh");
    params.stepSize = stepSize_;
    emit SetStepSize(stepSize);
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
      uint112 pricePoints_ = uint112(newParams.pricePoints);
      require(pricePoints_ == newParams.pricePoints && pricePoints_ >= 2, "Kandel/invalidPricePoints");
      setLength(pricePoints_);
      params.pricePoints = pricePoints_;
    }

    if (oldParams.stepSize != newParams.stepSize) {
      setStepSize(newParams.stepSize);
    }

    if (newParams.gasprice != 0 && newParams.gasprice != oldParams.gasprice) {
      setGasprice(newParams.gasprice);
    }

    if (newParams.gasreq != 0 && newParams.gasreq != oldParams.gasreq) {
      setGasreq(newParams.gasreq);
    }
  }

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, uint gasprice, address reserveId)
    TradesBaseQuotePair(olKeyBaseQuote)
    DirectWithBidsAndAsksDistribution(mgv, gasreq, reserveId)
  {
    setGasprice(gasprice);
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Care must be taken to publish offers in meaningful chunks. For Kandel an offer and its dual should be published in the same chunk (one being optionally initially dead).
  ///@param bidDistribution the distribution of prices for gives of quote for indices.
  ///@param askDistribution the distribution of prices for gives of base for indices.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different pricePoints or stepSize, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution memory bidDistribution,
    Distribution memory askDistribution,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) public payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkInternal(bidDistribution, askDistribution, params.gasreq, params.gasprice);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Care must be taken to publish offers in meaningful chunks. For Kandel an offer and its dual should be published in the same chunk (one being optionally initially dead).
  ///@notice This function is used externally after `populate` to reinitialize some indices or if multiple transactions are needed to split initialization due to gas cost.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param bidDistribution the distribution of prices for gives of quote for indices.
  ///@param askDistribution the distribution of prices for gives of base for indices.
  function populateChunk(Distribution calldata bidDistribution, Distribution calldata askDistribution)
    external
    onlyAdmin
  {
    Params memory parameters = params;
    populateChunkInternal(bidDistribution, askDistribution, parameters.gasreq, parameters.gasprice);
  }

  ///@inheritdoc AbstractKandel
  function reserveBalance(OfferType ba) public view virtual override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return token.balanceOf(address(this));
  }

  ///@notice takes care of status for updating dual and logging of potential issues.
  ///@param offerId the Mangrove offer id.
  ///@param args the arguments of the offer.
  ///@param updateOfferStatus the status returned from the `_updateOffer` function.
  function logUpdateOfferStatus(uint offerId, OfferArgs memory args, bytes32 updateOfferStatus) internal {
    if (updateOfferStatus == REPOST_SUCCESS || updateOfferStatus == "mgv/writeOffer/density/tooLow") {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    }
    emit LogIncident(args.olKey.hash(), offerId, "Kandel/updateOfferFailed", updateOfferStatus);
  }

  ///@notice update or create dual offer according to transport logic
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  function transportSuccessfulOrder(MgvLib.SingleOrder calldata order) internal {
    OfferType ba = offerTypeOfOutbound(IERC20(order.olKey.outbound));

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (uint offerId, OfferArgs memory args) = transportLogic(ba, order);

    // All offers are created up front (see populateChunk), so here we update to set new gives.
    bytes32 updateOfferStatus = _updateOffer(args, offerId);
    logUpdateOfferStatus(offerId, args, updateOfferStatus);
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

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return dualOfferId the offer id of the dual offer
  ///@return args the argument for updating an offer
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (uint dualOfferId, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;
    OfferType baDual = dual(ba);

    uint dualIndex = transportDestination(baDual, index, memoryParams.stepSize, memoryParams.pricePoints);

    dualOfferId = offerIdOfIndex(baDual, dualIndex);
    args.olKey = offerListOfOfferType(baDual);
    MgvStructs.OfferPacked dualOffer = MGV.offers(args.olKey, dualOfferId);

    // gives from order.takerGives:96 dualOffer.gives():96, so args.gives:97
    args.gives = order.takerGives + dualOffer.gives();
    if (uint96(args.gives) != args.gives) {
      // this should not be reached under normal circumstances unless strat is posting on top of an existing offer with an abnormal volume
      // to prevent gives to be too high, we let the surplus become "pending" (unpublished liquidity)
      args.gives = type(uint96).max;
    }

    args.logPrice = dualOffer.logPrice();

    // args.fund = 0; the offers are already provisioned
    // posthook should not fail if unable to post offers, we capture the error as incidents
    args.noRevert = true;
    args.gasprice = memoryParams.gasprice;
    args.gasreq = memoryParams.gasreq;
  }

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return the pending amount
  /// @dev Gas costly function, better suited for off chain calls.
  function pending(OfferType ba) external view override returns (int) {
    return int(reserveBalance(ba)) - int(offeredVolume(ba));
  }

  ///@notice Deposits funds to the contract's reserve
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public virtual override {
    require(TransferLib.transferTokenFrom(BASE, msg.sender, address(this), baseAmount), "Kandel/baseTransferFail");
    emit Credit(BASE, baseAmount);
    require(TransferLib.transferTokenFrom(QUOTE, msg.sender, address(this), quoteAmount), "Kandel/quoteTransferFail");
    emit Credit(QUOTE, quoteAmount);
  }

  ///@notice withdraws funds from the contract's reserve
  ///@param baseAmount the amount of base tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param quoteAmount the amount of quote tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param recipient the address to which the withdrawn funds should be sent to.
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) public virtual override onlyAdmin {
    if (baseAmount == type(uint).max) {
      baseAmount = BASE.balanceOf(address(this));
    }
    if (quoteAmount == type(uint).max) {
      quoteAmount = QUOTE.balanceOf(address(this));
    }
    require(TransferLib.transferToken(BASE, recipient, baseAmount), "Kandel/baseTransferFail");
    emit Debit(BASE, baseAmount);
    require(TransferLib.transferToken(QUOTE, recipient, quoteAmount), "Kandel/quoteTransferFail");
    emit Debit(QUOTE, quoteAmount);
  }

  ///@notice Retracts offers, withdraws funds, and withdraws free wei from Mangrove.
  ///@param from retract offers starting from this index.
  ///@param to retract offers until this index.
  ///@param baseAmount the amount of base tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param quoteAmount the amount of quote tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param freeWei the amount of wei to withdraw from Mangrove. Use type(uint).max to withdraw entire available balance.
  ///@param recipient the recipient of the funds.
  function retractAndWithdraw(
    uint from,
    uint to,
    uint baseAmount,
    uint quoteAmount,
    uint freeWei,
    address payable recipient
  ) external onlyAdmin {
    retractOffers(from, to);
    withdrawFunds(baseAmount, quoteAmount, recipient);
    withdrawFromMangrove(freeWei, recipient);
  }
}
