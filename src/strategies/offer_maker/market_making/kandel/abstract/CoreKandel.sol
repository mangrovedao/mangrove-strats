// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
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
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, address reserveId)
    TradesBaseQuotePair(olKeyBaseQuote)
    DirectWithBidsAndAsksDistribution(mgv, gasreq, reserveId)
  {}

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
    emit LogIncident(MGV, args.olKey.hash(), offerId, "Kandel/updateOfferFailed", updateOfferStatus);
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

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return offerId the offer id of the dual offer
  ///@return args the argument for updating an offer
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (uint offerId, OfferArgs memory args);

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
