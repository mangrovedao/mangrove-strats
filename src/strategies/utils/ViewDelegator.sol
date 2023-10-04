// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

///@title `IViewDelegator` is a util interface to delegate static calls to a contract.
interface IViewDelegator {
  /// @notice Function to use delegate calls in view functions
  /// @dev This function shall not be implemented but rather caught by the fallback function
  /// @param target The target contract to delegate the call to
  /// @param data The data to send to the target contract
  /// @return The data returned by the target contract
  function staticdelegatecall(address target, bytes memory data) external view returns (bytes memory);
}
