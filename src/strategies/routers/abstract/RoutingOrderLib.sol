// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title Library to obtain Routing orders of various kind

library RoutingOrderLib {
  ///@notice pointer to first storage slot used for randomized access
  bytes32 private constant OFFSET = keccak256("MangroveStrats.RoutingOrderLib.Layout");

  ///@notice Argument to pull/push
  ///@param token the asset to be routed
  ///@param olKeyHash the id of the market that triggered the calling offer logic. Is bytes32(0) when routing is done outside offer logic.
  ///@param offerId the id of the offer that triggered the calling offer logic. Is uint(0) when routing is done outsider offer logic.
  ///@param amount of token that needs to be routed
  ///@param PROXY_OWNER the owner of the calling router proxy.
  ///@dev PROXY_OWNER is capitalized to highlight the fact that is the address that was used to derive router proxy's address. It is passed here to minimize gas cost.
  struct RoutingOrder {
    IERC20 token;
    bytes32 olKeyHash;
    uint offerId;
    uint amount;
    address PROXY_OWNER;
  }

  ///@notice helper to create a RoutingOrder struct without zero'ed fields for market coordinates.
  ///@param token the asset to be routed
  ///@param amount of token to be routed
  ///@param proxyOwner the owner of the calling router proxy
  ///@return ro the routing order struct
  function createOrder(IERC20 token, address proxyOwner, uint amount) internal pure returns (RoutingOrder memory ro) {
    ro.token = token;
    ro.PROXY_OWNER = proxyOwner;
    ro.amount = amount;
  }

  ///@notice helper to create a RoutingOrder struct without zero'ed fields for market coordinates and amount.
  ///@param token the asset to be routed
  ///@param proxyOwner the owner of the calling router proxy
  ///@return ro the routing order struct
  function createOrder(IERC20 token, address proxyOwner) internal pure returns (RoutingOrder memory ro) {
    ro.token = token;
    ro.PROXY_OWNER = proxyOwner;
  }

  ///@notice the bound maker contracts which are allowed to call this router.
  struct Layout {
    mapping(address => bool) boundMakerContracts;
  }

  ///@notice allowed pullers/pushers for this router
  ///@return bound contracts to this router, in the form of a storage mapping
  function boundMakerContracts() internal view returns (mapping(address => bool) storage) {
    bytes32 offset = OFFSET;
    Layout storage st;
    assembly ("memory-safe") {
      st.slot := offset
    }
    return st.boundMakerContracts;
  }
}
