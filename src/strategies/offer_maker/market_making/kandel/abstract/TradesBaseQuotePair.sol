// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title a bid or an ask.
enum OfferType {
  Bid,
  Ask
}

///@title Interface contract for strats needing offer type to offer list mapping.
abstract contract IHasOfferListOfOfferType {
  ///@notice turns an offer type into an (outbound, inbound, tickScale) pair identifying an offer list.
  ///@param ba whether one wishes to access the offer lists where asks or bids are posted.
  ///@return olKey the olKey defining the token pair
  function offerListOfOfferType(OfferType ba) internal view virtual returns (OLKey memory olKey);

  ///@notice returns the offer type of the offer list whose outbound token is given in the argument.
  ///@param outbound_tkn the outbound token
  ///@return ba the offer type
  function offerTypeOfOutbound(IERC20 outbound_tkn) internal view virtual returns (OfferType ba);

  ///@notice returns the outbound token for the offer type
  ///@param ba the offer type
  ///@return token the outbound token
  function outboundOfOfferType(OfferType ba) internal view virtual returns (IERC20 token);
}

///@title Adds basic base/quote trading pair for bids and asks and couples it to Mangrove's gives, wants, outbound, inbound terminology.
///@dev Implements the IHasOfferListOfOfferType interface contract.
abstract contract TradesBaseQuotePair is IHasOfferListOfOfferType {
  ///@notice base of the market Kandel is making
  IERC20 public immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 public immutable QUOTE;
  ///@notice tickScale of the market Kandel is making
  uint public immutable TICK_SCALE;

  ///@notice The traded pair
  ///@param base of the market Kandel is making
  ///@param quote of the market Kandel is making
  ///@param tickScale the tickScale of the market
  event OfferListKey(IERC20 base, IERC20 quote, uint tickScale);

  ///@notice Constructor
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  constructor(OLKey memory olKeyBaseQuote) {
    BASE = IERC20(olKeyBaseQuote.outbound);
    QUOTE = IERC20(olKeyBaseQuote.inbound);
    TICK_SCALE = olKeyBaseQuote.tickScale;
    emit OfferListKey(BASE, QUOTE, TICK_SCALE);
  }

  ///@inheritdoc IHasOfferListOfOfferType
  function offerListOfOfferType(OfferType ba) internal view override returns (OLKey memory olKey) {
    return ba == OfferType.Bid
      ? OLKey(address(QUOTE), address(BASE), TICK_SCALE)
      : OLKey(address(BASE), address(QUOTE), TICK_SCALE);
  }

  ///@inheritdoc IHasOfferListOfOfferType
  function offerTypeOfOutbound(IERC20 outbound_tkn) internal view override returns (OfferType) {
    return outbound_tkn == BASE ? OfferType.Ask : OfferType.Bid;
  }

  ///@inheritdoc IHasOfferListOfOfferType
  function outboundOfOfferType(OfferType ba) internal view override returns (IERC20 token) {
    token = ba == OfferType.Ask ? BASE : QUOTE;
  }

  ///@notice returns the dual offer type
  ///@param ba whether the offer is an ask or a bid
  ///@return baDual is the dual offer type (ask for bid and conversely)
  function dual(OfferType ba) internal pure returns (OfferType baDual) {
    return OfferType((uint(ba) + 1) % 2);
  }
}
