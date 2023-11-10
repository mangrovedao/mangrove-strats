// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title Library to obtain Routing orders of various kind

library RoutingOrderLib {
  bytes32 private constant OFFSET = keccak256("MangroveStrats.RoutingOrderLib.Layout");

  ///@notice Argument to pull/push
  ///@param token the asset to be routed
  ///@param olKeyHash the id of the market that triggered the calling offer logic. Is bytes32(0) when routing is done outside offer logic.
  ///@param offerId the id of the offer that triggered the calling offer logic. Is uint(0) when routing is done outsider offer logic.
  ///@param amount of token that needs to be routed
  ///@param reserveId address of the account holding the funds to be routed
  struct RoutingOrder {
    IERC20 token;
    bytes32 olKeyHash;
    uint offerId;
    uint amount;
    address reserveId;
  }

  function createOrder(IERC20 token, uint amount, address reserveId) internal pure returns (RoutingOrder memory ro) {
    ro.token = token;
    ro.amount = amount;
    ro.reserveId = reserveId;
  }

  function createOrder(IERC20 token, address reserveId) internal pure returns (RoutingOrder memory ro) {
    ro.token = token;
    ro.reserveId = reserveId;
  }

  ///@notice the bound maker contracts which are allowed to call this router.
  struct Layout {
    mapping(address => bool) boundMakerContracts;
  }

  function boundMakerContracts() internal view returns (mapping(address => bool) storage) {
    bytes32 offset = OFFSET;
    Layout storage st;
    assembly ("memory-safe") {
      st.slot := offset
    }
    return st.boundMakerContracts;
  }
}
