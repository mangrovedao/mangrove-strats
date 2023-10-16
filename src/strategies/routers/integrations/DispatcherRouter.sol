// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MultiRouter, MonoRouter, AbstractRouter, ApprovalInfo} from "../abstract/MultiRouter.sol";
import {IERC20} from "@mgv/src/core/MgvLib.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title `Dispatcher` delegates calls to the correct router contract depending on the token and reserveId sourcing strategy.
contract DispatcherRouter is MultiRouter {
  ///@notice WhiteList of allowed routers
  mapping(MonoRouter => bool) public allowedRouters;

  /// @notice WhiteList a router contract
  /// @dev This event is emitted when a router contract is whitelisted
  /// @param router The router contract that was whitelisted
  event AddedAllowedRouter(MonoRouter indexed router);

  /// @notice Remove a router contract from the whitelist
  /// @dev This event is emitted when a router contract is removed from the whitelist
  /// @param router The router contract that was removed from the whitelist
  event RemovedAllowedRouter(MonoRouter indexed router);

  /// @notice Initializes a new router contract.
  /// @dev Whitelists a given router contract.
  /// @param router The router contract to initialize
  function initializeRouter(MonoRouter router) external onlyAdmin {
    require(!allowedRouters[router], "Dispatcher/RouterAlreadySet");
    allowedRouters[router] = true;
    emit AddedAllowedRouter(router);
  }

  /// @notice Removes a router contract from the whitelist.
  /// @dev Throws if the router contract is not whitelisted.
  /// @param router The router contract to remove
  function removeRouter(MonoRouter router) external onlyAdmin {
    require(allowedRouters[router], "Dispatcher/RouterNotSet");
    allowedRouters[router] = false;
    emit RemovedAllowedRouter(router);
  }

  /// @notice Get the current router for the given token and reserveId
  /// @dev This will revert if the router contract does not exist
  /// @param token The token to get the router for
  /// @param reserveId The reserveId to get the router for
  /// @return router The MonoRouter contract
  function _getRouterSafely(IERC20 token, address reserveId) internal view returns (MonoRouter router) {
    router = routes[token][reserveId];
    // TODO: should we set a default router in cas of address(0)?
    require(allowedRouters[router], "Dispatcher/RouterNotSet");
  }

  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint, bool, ApprovalInfo calldata)
    internal
    virtual
    override
    returns (uint)
  {
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

  /// @notice Calls a function of a specific router implementation and mutates data
  /// @dev the function that receive the call must have the data as follows (address, IERC20, bytes calldata)
  /// * only the maker contract can call this function
  /// @param selector The selector of the function to call
  /// @param reserveId The reserveId to call the function on
  /// @param token The token to call the function on
  /// @param data The data to call the function with
  function mutateRouterState(bytes4 selector, address reserveId, IERC20 token, bytes calldata data)
    external
    onlyCaller(reserveId)
  {
    address router = address(_getRouterSafely(token, reserveId));
    require(router != address(0), "Dispatcher/SelectorNotSet");
    (bool success, bytes memory retdata) = router.delegatecall(abi.encodeWithSelector(selector, reserveId, token, data));
    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/RouterSpecificFunctionFailed");
      }
    }
  }

  /// @notice Calls a function of a specific router implementation and queries data
  /// @dev the function that receive the call must have the data as follows (address, IERC20, bytes calldata)
  /// * only the maker contract can call this function
  /// @param selector The selector of the function to call
  /// @param reserveId The reserveId to call the function on
  /// @param token The token to call the function on
  /// @param data The data to call the function with
  /// @return retdata The data returned by the router
  function queryRouterState(bytes4 selector, address reserveId, IERC20 token, bytes calldata data)
    external
    view
    returns (bytes memory)
  {
    reserveId;
    token;
    data;

    address router = address(_getRouterSafely(token, reserveId));
    require(router != address(0), "Dispatcher/SelectorNotSet");
    (bool success, bytes memory retdata) = address(this).staticcall(
      abi.encodeWithSelector(
        this._staticdelegatecall.selector, router, abi.encodeWithSelector(selector, reserveId, token, data)
      )
    );

    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/RouterSpecificFunctionFailed");
      }
    }
    return retdata;
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

  /// @inheritdoc	AbstractRouter
  function __activate__(IERC20) internal virtual override {
    revert("Dispatcher/NoRouterSpecified");
  }

  /// @notice Activates a router for a given token
  /// @dev This implementation overrides the AbstractRouter implementation to allow for a router to be activated
  /// * Throws if the router is not bound
  /// @param token The token to activate the router for
  /// @param router The router to activate
  function activate(IERC20 token, MonoRouter router) external boundOrAdmin {
    (bool success, bytes memory retdata) =
      address(router).delegatecall(abi.encodeWithSelector(AbstractRouter.activate.selector, token));
    if (!success) {
      if (retdata.length > 0) {
        assembly {
          let returndata_size := mload(retdata)
          revert(add(0x20, retdata), returndata_size)
        }
      } else {
        revert("Dispatcher/ActivateFailed");
      }
    }
  }
}
