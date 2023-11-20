// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {AbstractRouter} from "./abstract/AbstractRouter.sol";

/// @title Mangrove Router Proxy
/// @notice A proxy contract that delegates calls to an instance of an AbstractRouter contract.
///         It does not allow updates of implementation contract.
contract RouterProxy {
  /// @notice The address of the deployed SmartRouter contract acting as the delegate implementation.
  /// @dev The SmartRouter instance must be AccessControlled to ensure the storage layout is matched.
  AbstractRouter public immutable IMPLEMENTATION;

  /// @notice Deploys a Proxy for the SmartRouter that handles incoming transactions and delegates them to the implementation.
  /// @param implementation The address of the deployed SmartRouter contract to which calls will be delegated.
  /// @dev Initializes the contract with an AccessControlled base to set up access control.
  constructor(AbstractRouter implementation) {
    IMPLEMENTATION = implementation;
    // store the msg sender at address 0 (_admin storage slot on access controlled)
    // We do not want to store the whole AccessControlled logic inside the proxy
    assembly {
      sstore(0, caller())
    }
  }

  /// @notice Fallback function to receive ETH.
  /// @dev This function is marked as virtual so it can be overridden by inheriting contracts if required.
  receive() external payable virtual {}

  /// @notice Fallback function to delegate calls to the implementation contract.
  fallback() external payable {
    AbstractRouter implementation = IMPLEMENTATION;
    assembly {
      // Copy msg.data. We take full control of memory in this inline assembly
      // block because it will not return to Solidity code. We overwrite the
      // Solidity scratch pad at memory position 0.
      calldatacopy(0, 0, calldatasize())

      // Call the implementation.
      // out and outsize are 0 because we don't know the size yet.
      let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

      // Copy the returned data.
      returndatacopy(0, 0, returndatasize())

      switch result
      // delegatecall returns 0 on error.
      case 0 { revert(0, returndatasize()) }
      default { return(0, returndatasize()) }
    }
  }
}
