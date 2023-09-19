// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MonoRouter} from "./MonoRouter.sol";
import {AbstractRouter} from "./AbstractRouter.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title `DispatchedRouter` instances should be delegated called by a dispatcher.
///@dev no call should be made directly to this contract as storage may not be initialized.
abstract contract DispatchedRouter is MonoRouter(0) {
  /// @notice Storage Key for global router storage
  bytes32 public immutable DISPATCHED_ROUTER_STORAGE_KEY;

  /// @notice Storage Key for specific router behavior storage
  bytes32 public immutable ROUTER_STORAGE_KEY;

  constructor(bytes memory storage_key) {
    ROUTER_STORAGE_KEY = keccak256(storage_key);
    bytes32 dispatched_router_key = keccak256("DispatchedRouter.key");
    DISPATCHED_ROUTER_STORAGE_KEY = keccak256(abi.encodePacked(ROUTER_STORAGE_KEY, dispatched_router_key));
  }

  // TODO: check if we need to add a disabled flag to the router
  struct DispatchedRouterStorage {
    bool initialized;
  }

  /// @notice Initializes the router storage
  /// @dev This function must be called by the dispatcher before any other call to the router
  /// @param initData The data to be passed to the router's initialize function
  /// @return initialized if the router was successfully initialized
  function initialize(bytes calldata initData) public returns (bool initialized) {
    DispatchedRouterStorage storage s = _getDispatchedRouterStorage();
    require(!s.initialized, "DispatchedRouter/Initialized");
    initialized = __initialize__(initData);
    s.initialized = initialized;
  }

  /// @notice Hook for router initialization
  /// @dev This function must be implemented by the dispatched router and initilize storage for the given router
  /// @param initData The data to be passed to the router's initialize function
  /// @return initialized if the router was successfully initialized
  function __initialize__(bytes calldata initData) internal virtual returns (bool);

  /// @notice Gets the router storage slot
  /// @dev This function returns the Dispatched router storage at the correct slot
  /// @return s The DispatchedRouterStorage at the correct slot
  function _getDispatchedRouterStorage() internal view returns (DispatchedRouterStorage storage s) {
    bytes32 slot = DISPATCHED_ROUTER_STORAGE_KEY;
    assembly {
      s.slot := slot
    }
  }

  /// @notice Maximum amount of the underlying asset that can be deposited
  /// @dev Must return the maximum amount of `token` that can be deposited (type(uint256).max if no limit)
  /// @param token The token to be deposited
  /// @return maxDeposit The maximum amount of the underlying asset that can be deposited
  function maxDeposit(IERC20 token) public view virtual returns (uint);

  /// @notice Maximum amount of the underlying asset that can be withdrawn
  /// @dev Must return the maximum amount of `token` that can be withdrawn (type(uint256).max if no limit)
  /// @param token The token to be withdrawn
  /// @return maxWithdraw The maximum amount of the underlying asset that can be withdrawn
  function maxWithdraw(IERC20 token) public view virtual returns (uint);

  /// @notice Preview the amount of underlying asset that would be deposited
  /// @dev Must return the amount of shares received by depositing `amount` of `token`
  /// @param token The token to be deposited
  /// @param amount The amount of `token` to be deposited
  /// @return shares The amount of shares received
  function previewDeposit(IERC20 token, uint amount) public view virtual returns (uint);

  /// @notice Preview the amount of shares that would be withdrawn
  /// @dev Must return the amount of `shares` burned by withdrawing `amount` of `token`
  /// @param token The token to be withdrawn
  /// @param amount The amount of `token` to be withdrawn
  /// @return shares The amount of shares burned
  function previewWithdraw(IERC20 token, uint amount) public view virtual returns (uint);
}
