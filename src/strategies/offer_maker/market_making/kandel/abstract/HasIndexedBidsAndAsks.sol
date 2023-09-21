// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IHasOfferListOfOfferType, OfferType} from "./TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title Adds a [0..length] index <--> offerId map to a strat.
///@dev utilizes the `IHasOfferListOfOfferType` contract.
abstract contract HasIndexedBidsAndAsks is IHasOfferListOfOfferType {
  ///@notice The Mangrove deployment.
  IMangrove private immutable MGV;

  ///@notice the length of the index has been set.
  ///@param value the length.
  ///@notice By emitting this data, an indexer will be able to keep track of what length is used.
  event SetLength(uint value);

  ///@notice a new offer of type `ba` with `offerId` was created at price `index`
  ///@param ba the offer type
  ///@param index the index
  ///@param offerId the Mangrove offer id.
  ///@notice By emitting this data, an indexer will be able to keep track of what offer has what index.
  event SetIndexMapping(OfferType indexed ba, uint index, uint offerId);

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  constructor(IMangrove mgv) {
    MGV = mgv;
  }

  ///@notice the length of the map.
  uint internal length;

  ///@notice Mangrove's offer id of an ask at a given index.
  mapping(uint => uint) private askOfferIdOfIndex;
  ///@notice Mangrove's offer id of a bid at a given index.
  mapping(uint => uint) private bidOfferIdOfIndex;

  ///@notice An inverse mapping of askOfferIdOfIndex. E.g., indexOfAskOfferId[42] is the index in askOfferIdOfIndex at which ask of id #42 on Mangrove is stored.
  mapping(uint => uint) private indexOfAskOfferId;

  ///@notice An inverse mapping of bidOfferIdOfIndex. E.g., indexOfBidOfferId[42] is the index in bidOfferIdOfIndex at which bid of id #42 on Mangrove is stored.
  mapping(uint => uint) private indexOfBidOfferId;

  ///@notice maps index of offers to offer id on Mangrove.
  ///@param ba the offer type
  ///@param index the index
  ///@return offerId the Mangrove offer id.
  function offerIdOfIndex(OfferType ba, uint index) public view returns (uint offerId) {
    return ba == OfferType.Ask ? askOfferIdOfIndex[index] : bidOfferIdOfIndex[index];
  }

  ///@notice Maps an offer type and Mangrove offer id to index.
  ///@param ba the offer type
  ///@param offerId the Mangrove offer id.
  ///@return index the index.
  function indexOfOfferId(OfferType ba, uint offerId) public view returns (uint index) {
    return ba == OfferType.Ask ? indexOfAskOfferId[offerId] : indexOfBidOfferId[offerId];
  }

  ///@notice Sets the Mangrove offer id for an index and vice versa.
  ///@param ba the offer type
  ///@param index the index
  ///@param offerId the Mangrove offer id.
  function setIndexMapping(OfferType ba, uint index, uint offerId) internal {
    if (ba == OfferType.Ask) {
      indexOfAskOfferId[offerId] = index;
      askOfferIdOfIndex[index] = offerId;
    } else {
      indexOfBidOfferId[offerId] = index;
      bidOfferIdOfIndex[index] = offerId;
    }
    emit SetIndexMapping(ba, index, offerId);
  }

  ///@notice sets the length of the map.
  ///@param length_ the new length.
  function setLength(uint length_) internal {
    length = length_;
    emit SetLength(length_);
  }

  ///@notice gets the Mangrove offer at the given index for the offer type.
  ///@param ba the offer type.
  ///@param index the index.
  ///@return offer the Mangrove offer.
  function getOffer(OfferType ba, uint index) public view returns (MgvStructs.OfferPacked offer) {
    uint offerId = offerIdOfIndex(ba, index);
    OLKey memory olKey = offerListOfOfferType(ba);
    offer = MGV.offers(olKey, offerId);
  }

  /// @notice gets the total gives of all offers of the offer type.
  /// @param ba offer type.
  /// @return volume the total gives of all offers of the offer type.
  /// @dev function is very gas costly, for external calls only.
  function offeredVolume(OfferType ba) public view returns (uint volume) {
    for (uint index = 0; index < length; ++index) {
      MgvStructs.OfferPacked offer = getOffer(ba, index);
      volume += offer.gives();
    }
  }
}
