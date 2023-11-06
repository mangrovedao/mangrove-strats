// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {Proxy} from "@openzeppelin/contracts/proxy/proxy.sol";
import {SmartRouter} from "./SmartRouter.sol";

///@title Mangrove Smart Router Proxy
///@dev This contract is supposedly `AccessControlled` but to reduce the gas cost of deploying it, we removed the `AccessControlled` inheritance.
///* Storage slot for the `_admin` internal variables of subsequent delegate calls **has to be** `0x00`
///* AccessControlled is verified by the deployed `SmartRouter` implementation.
contract SmartRouterProxy is Proxy {
  /// @notice The implementation address of the proxy
  /// @dev The implementation is an `AccessControlled` SmartRouter instance
  SmartRouter public immutable IMPLEMENTATION;

  /// @notice contract constructor
  /// @dev sets the caller (sender) at the 0x00 storage slot setting the admin field to the caller
  /// @param implementation The implementation address of the proxy
  constructor(SmartRouter implementation) {
    IMPLEMENTATION = implementation;
    // stores the caller address in storage slot 0x0 => this is the admin field
    assembly {
      sstore(0x0, caller())
    }
  }

  ///@inheritdoc Proxy
  function _implementation() internal view override returns (address) {
    return address(IMPLEMENTATION);
  }
}
