// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DelegatedRenegingForwarder} from "./DelegatedRenegingForwarder.sol";
import {IOfferLogic} from "./abstract/Forwarder.sol";

library DelegatedRFLib {
  function delegateCallWithData(address target, bytes memory data) internal returns (bytes memory) {
    (bool success, bytes memory returnData) = target.delegatecall(data);
    if (!success) {
      if (returnData.length > 0) {
        assembly {
          let returnDataSize := mload(returnData)
          revert(add(32, returnData), returnDataSize)
        }
      } else {
        revert("DelegatedRFLib: delegatecall failed");
      }
    }
    return returnData;
  }

  /**
   * @dev Creates a new offer using the provided arguments and the DelegatedRenegingForwarder contract.
   * @param args The arguments for the offer.
   * @param owner The address of the offer owner.
   * @param forwarder The DelegatedRenegingForwarder contract instance.
   * @return offerId The ID of the newly created offer.
   * @return status The status of the offer.
   */
  function newOffer(IOfferLogic.OfferArgs memory args, address owner, DelegatedRenegingForwarder forwarder)
    internal
    returns (uint offerId, bytes32 status)
  {
    bytes memory data = abi.encodeWithSelector(forwarder.internalNewOffer.selector, args, owner);
    bytes memory returnData = delegateCallWithData(address(forwarder), data);
    (offerId, status) = abi.decode(returnData, (uint, bytes32));
  }

  /**
   * @dev Updates an offer using the DelegatedRenegingForwarder contract.
   * @param args The offer arguments.
   * @param offerId The ID of the offer to update.
   * @param forwarder The DelegatedRenegingForwarder contract instance.
   * @return reason The reason for the update, encoded as bytes32.
   */
  function updateOffer(IOfferLogic.OfferArgs memory args, uint offerId, DelegatedRenegingForwarder forwarder)
    internal
    returns (bytes32 reason)
  {
    bytes memory data = abi.encodeWithSelector(forwarder.internalUpdateOffer.selector, args, offerId);
    bytes memory returnData = delegateCallWithData(address(forwarder), data);
    (reason) = abi.decode(returnData, (bytes32));
  }

  ///@notice Updates the expiry date and the max volume for a specific offer if caller is the offer owner.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The offer id whose expiry date and max volume is to be set.
  ///@param expiryDate in seconds since unix epoch. Use 0 for no expiry.
  ///@param volume the amount of outbound tokens above which the offer should renege on trade.
  ///@param forwarder The DelegatedRenegingForwarder contract instance.
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  /// * While updating, the volume should be set to 0. Otherwise, we create a renege for no reason.
  /// * If the user wants to reduce the promised volume, he should update his offer directly.
  /// * If we had to use max volume to avoid reneging with minimum volume, the user could update the offer by himself and set volume back to 0.
  function setReneging(
    bytes32 olKeyHash,
    uint offerId,
    uint expiryDate,
    uint volume,
    DelegatedRenegingForwarder forwarder
  ) internal {
    bytes memory data = abi.encodeWithSelector(forwarder.setReneging.selector, olKeyHash, offerId, expiryDate, volume);
    delegateCallWithData(address(forwarder), data);
  }

  function ownerOf(bytes32 olKeyHash, uint offerId, DelegatedRenegingForwarder forwarder)
    internal
    returns (address owner)
  {
    bytes memory data = abi.encodeWithSelector(forwarder.ownerOf.selector, olKeyHash, offerId);
    bytes memory returnData = delegateCallWithData(address(forwarder), data);
    (owner) = abi.decode(returnData, (address));
  }
}
