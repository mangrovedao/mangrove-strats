// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {AbstractRouter} from "./abstract/AbstractRouter.sol";

/// @title Mangrove Router Proxy
/// @notice A proxy contract that delegates calls to an instance of an AbstractRouter contract.
///         It does not allow updates of implementation contract.
contract RouterProxy is AccessControlled, Proxy {
  /// @notice The address of the deployed SmartRouter contract acting as the delegate implementation.
  /// @dev The SmartRouter instance must be AccessControlled to ensure the storage layout is matched.
  AbstractRouter public immutable IMPLEMENTATION;

  /// @notice Deploys a Proxy for the SmartRouter that handles incoming transactions and delegates them to the implementation.
  /// @param implementation The address of the deployed SmartRouter contract to which calls will be delegated.
  /// @dev Initializes the contract with an AccessControlled base to set up access control.
  constructor(AbstractRouter implementation) AccessControlled(msg.sender) Proxy() {
    IMPLEMENTATION = implementation;
  }

  /// @notice Fallback function to receive ETH.
  /// @dev This function is marked as virtual so it can be overridden by inheriting contracts if required.
  receive() external payable virtual {}

  /// @notice Retrieves the (immutable) implementation address used by the proxy.
  /// @return The address of the SmartRouter implementation.
  function _implementation() internal view override returns (address) {
    return address(IMPLEMENTATION);
  }
}
