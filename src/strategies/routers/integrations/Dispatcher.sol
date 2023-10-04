// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MultiRouter, MonoRouter, AbstractRouter} from "../abstract/MultiRouter.sol";
import {IERC20} from "mgv_src/core/MgvLib.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {IViewDelegator} from "../../utils/ViewDelegator.sol";

abstract contract IDelegatedRouter {
  function delegatedCheckList(IERC20 token, address reserveId) external view virtual;
}

/// @title `Dispatcher` delegates calls to the correct router contract depending on the token and reserveId sourcing strategy.
contract Dispatcher is MultiRouter {
  mapping(bytes4 => address) public routerSpecificFunctions;

  /// @notice Fired when a router specific function is added to the dispatcher
  /// @dev This must be fired for the indexers to pick up the function
  /// @param router The dispatched router contract
  /// @param selector The function selector
  event RouterSpecificFunctionAdded(address indexed router, bytes4 indexed selector);

  /// @notice Fired when a router specific function is removed from the dispatcher
  /// @param router The dispatched router contract
  /// @param selector The function selector
  event RouterSpecificFunctionRemoved(address indexed router, bytes4 indexed selector);

  /// @notice Initializes a new router contract by setting the router specific functions
  /// @dev Selectors must be unique across all routers
  /// * if a selector is already set, it will revert
  /// @param router The router contract to initialize
  /// @param selectors The selectors to set
  function initializeRouter(address router, bytes4[] calldata selectors) external onlyBound {
    for (uint i = 0; i < selectors.length; i++) {
      require(routerSpecificFunctions[selectors[i]] == address(0), "Dispatcher/SelectorAlreadySet");
      routerSpecificFunctions[selectors[i]] = router;
      emit RouterSpecificFunctionAdded(router, selectors[i]);
    }
  }

  /// @notice Removes a router contract by removing the router specific functions
  /// @dev if a selector is not set, it will revert
  /// @param selectors The selectors to remove
  function removeFunctions(bytes4[] calldata selectors) external onlyBound {
    for (uint i = 0; i < selectors.length; i++) {
      address router = routerSpecificFunctions[selectors[i]];
      require(router != address(0), "Dispatcher/SelectorNotSet");
      delete routerSpecificFunctions[selectors[i]];
      emit RouterSpecificFunctionRemoved(router, selectors[i]);
    }
  }

  /// @notice Get the current router for the given token and reserveId
  /// @dev This will revert if the router contract does not exist
  /// @param token The token to get the router for
  /// @param reserveId The reserveId to get the router for
  /// @return router The MonoRouter contract
  function _getRouterSafely(IERC20 token, address reserveId) internal view returns (MonoRouter router) {
    router = routes[token][reserveId];
    // TODO: check if we set a default route for gas costs
    require(address(router) != address(0), "Dispatcher/UnkownRoute");
  }

  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint, bool) internal virtual override returns (uint) {
    address router = address(_getRouterSafely(token, reserveId));
    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), router, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 { revert(0, returndatasize()) }
      default { return(0, returndatasize()) }
    }
  }

  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint) internal virtual override returns (uint) {
    address router = address(_getRouterSafely(token, reserveId));
    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), router, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 { revert(0, returndatasize()) }
      default { return(0, returndatasize()) }
    }
  }

  /// @inheritdoc	AbstractRouter
  function __checkList__(IERC20 token, address reserveId, address) internal view virtual override {
    MonoRouter router = _getRouterSafely(token, reserveId);
    (bool success, bytes memory retdata) =
      address(this).staticcall(abi.encodeWithSelector(this._staticdelegatecall.selector, address(router), msg.data));
    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/ChecklistFailed");
      }
    }
  }

  /// @inheritdoc	AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    // return token.balanceOf(reserveId);
    MonoRouter router = _getRouterSafely(token, reserveId);
    (bool success, bytes memory retdata) =
      address(this).staticcall(abi.encodeWithSelector(this._staticdelegatecall.selector, address(router), msg.data));
    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/BalanceOfReserveFailed");
      }
    }
    assembly {
      return(add(retdata, 32), returndatasize())
    }
  }

  /// @notice Calls a function of a specific router implementation
  /// @dev the function that receive the call must have the data as follows (address, IERC20, bytes calldata)
  /// * only the maker contract can call this function
  /// @param selector The selector of the function to call
  /// @param reserveId The reserveId to call the function on
  /// @param token The token to call the function on
  /// @param data The data to call the function with
  function callRouterSpecificFunction(bytes4 selector, address reserveId, IERC20 token, bytes calldata data)
    external
    onlyBound
  {
    address router = routerSpecificFunctions[selector];
    require(router != address(0), "Dispatcher/SelectorNotSet");
    (bool success,) = router.delegatecall(abi.encodeWithSelector(selector, reserveId, token, data));
    require(success, "Dispatcher/RouterSpecificFunctionFailed");
  }

  /// @notice intermediate function to allow a call to be delagated to `target` while preserving the a `view` attribute
  /// @dev scheme is as follows: for some `view` function `f` of `target`, one does `staticcall(_staticdelegatecall(target, f))` which will retain for the `view` attribute
  /// * this implementation does not preserve the `msg.sender` and `msg.data`
  /// @param target The address to delegate the call to
  /// @param data The data to call the function with
  function _staticdelegatecall(address target, bytes calldata data) external {
    require(msg.sender == address(this), "Dispatcher/internalOnly");
    (bool success, bytes memory retdata) = target.delegatecall(data);
    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/StaticDelegateCallFailed");
      }
    }
    assembly {
      return(add(retdata, 32), returndatasize())
    }
  }
}
