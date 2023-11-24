// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRoutingLogic} from "../routing_logic/abstract/AbstractRoutingLogic.sol";

/// @title Mangrove Smart Router Storage
/// @notice This library provides a storage layout for the Mangrove Smart Router, utilizing a unique namespace to avoid storage collisions.
/// @dev The storage layout is defined within a struct and accessed via a constant offset to prevent conflicts with storage in other contracts when used with delegate calls.
library SmartRouterStorage {
  /// @notice The unique offset for the library's storage layout to prevent storage slot collisions.
  bytes32 private constant OFFSET = keccak256("MangroveStrats.SmartRouterStorage.Layout");

  /// @notice Defines the structure of the storage layout used by the Smart Router.
  /// @dev Contains a nested mapping to associate tokens and offer IDs with their respective logic contracts.
  struct Layout {
    mapping(IERC20 token => mapping(bytes32 olKeyHash => mapping(uint offerId => AbstractRoutingLogic logic)))
      routeLogics;
  }

  /// @notice Retrieves a reference to the storage layout for the Smart Router.
  /// @return st A reference to the library's storage layout struct.
  function getStorage() internal pure returns (Layout storage st) {
    bytes32 offset = OFFSET;
    assembly ("memory-safe") {
      st.slot := offset
    }
  }

  /**
   * @notice An intermediate function to allow a call to be delegated to an implementation while preserving the `view` attribute.
   * @param impl The address of the implementation to which the call will be delegated.
   * @param data The calldata to be sent to the implementation.
   * @dev usage, for a view funciton `f(args)` of a contract `C c`, is as follows:
   *  ```(bool success, bytes memory retdata) = address(this).staticcall(
   *         address(c),
   *       abi.encodeWithSelector(
   *         SmartRouterStorage._staticdelegatecall.selector,
   *         abi.encodeWithSelector(C.f.selector, args)
   *       )
   *     );
   *  ```
   */
  function _staticdelegatecall(address impl, bytes calldata data) external {
    /// makes sure that a call to this function is a pseudo internal call.
    require(msg.sender == address(this), "SmartRouterStorage/internalOnly");
    (bool success, bytes memory retdata) = impl.delegatecall(data);
    if (!success) {
      revertWithData(retdata);
    }
    assembly ("memory-safe") {
      return(add(retdata, 32), returndatasize())
    }
  }

  /// @notice Propagates a revert with reason from a failed delegate call.
  /// @param retdata The return data from the delegate call that caused the revert.
  /// @dev This function uses inline assembly to revert with the exact error message from the delegate call.
  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("SmartRouter/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }
}
