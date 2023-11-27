// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {RL, AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

///@title IForwarder
///@notice Interface for contracts that manage liquidity on Mangrove on behalf of multiple offer makers
interface IForwarder {
  ///@notice Logging new offer owner
  ///@param olKeyHash the hash of the offer list key. This is indexed to allow RPC calls to filter on it.
  ///@param offerId the Mangrove offer id. This is indexed to allow RPC calls to filter on it.
  ///@param owner the offer maker that can manage the offer. It is indexed to allow RPC calls to filter on it.
  ///@notice By emitting this data, an indexer will be able to keep track of the real owner of an offer
  event NewOwnedOffer(bytes32 indexed olKeyHash, uint indexed offerId, address indexed owner);

  /// @notice view on an offer owner.
  /// @param olKeyHash the hash of the offer list key.
  /// @param offerId the offer identifier on the offer list.
  /// @return owner the offer maker that can manage the offer.
  /// @dev `ownerOf(in,out,id)` is equivalent to `offerOwners(in, out, [id])` but more gas efficient.
  function ownerOf(bytes32 olKeyHash, uint offerId) external view returns (address owner);
}
