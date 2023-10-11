// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MultiRouter, MonoRouter, AbstractRouter, ApprovalInfo} from "../abstract/MultiRouter.sol";
import {IERC20} from "mgv_src/core/MgvLib.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

/// @title `Dispatcher` delegates calls to the correct router contract depending on the token and reserveId sourcing strategy.
contract Dispatcher is MultiRouter {
  /// @notice Holds signatures for the functions that can be called to mutate the state on the router contracts
  mapping(bytes4 => address) public mutatorFunctions;

  /// @notice Holds signatures for the functions that can be called to query the state on the router contracts
  mapping(bytes4 => address) public accessorFunctions;

  /// @notice Fired when a router specific function is added to the dispatcher
  /// @dev This must be fired for the indexers to pick up the function
  /// @param router The dispatched router contract
  /// @param selector The function selector
  /// @param isMutator Whether the function is a mutator or not
  event RouterSpecificFunctionAdded(address indexed router, bytes4 indexed selector, bool indexed isMutator);

  /// @notice Fired when a router specific function is removed from the dispatcher
  /// @param router The dispatched router contract
  /// @param selector The function selector
  /// @param isMutator Whether the function is a mutator or not
  event RouterSpecificFunctionRemoved(address indexed router, bytes4 indexed selector, bool indexed isMutator);

  /// @notice Initializes a new router contract by setting the router specific functions
  /// @dev Selectors must be unique across all routers
  /// * if a selector is already set, it will revert
  /// @param router The router contract to initialize
  /// @param mutators The mutator functions to set
  /// @param accessors The accessor functions to set
  function initializeRouter(address router, bytes4[] calldata mutators, bytes4[] calldata accessors) external onlyBound {
    for (uint i = 0; i < mutators.length; i++) {
      require(mutatorFunctions[mutators[i]] == address(0), "Dispatcher/SelectorAlreadySet");
      mutatorFunctions[mutators[i]] = router;
      emit RouterSpecificFunctionAdded(router, mutators[i], true);
    }
    for (uint i = 0; i < accessors.length; i++) {
      require(accessorFunctions[accessors[i]] == address(0), "Dispatcher/SelectorAlreadySet");
      accessorFunctions[accessors[i]] = router;
      emit RouterSpecificFunctionAdded(router, accessors[i], false);
    }
  }

  /// @notice Removes a router contract by removing the router specific functions
  /// @dev if a selector is not set, it will revert
  /// @param mutators The mutator functions to remove
  /// @param accessors The accessor functions to remove
  function removeFunctions(bytes4[] calldata mutators, bytes4[] calldata accessors) external onlyBound {
    for (uint i = 0; i < mutators.length; i++) {
      require(mutatorFunctions[mutators[i]] != address(0), "Dispatcher/SelectorNotSet");
      mutatorFunctions[mutators[i]] = address(0);
      emit RouterSpecificFunctionRemoved(mutatorFunctions[mutators[i]], mutators[i], true);
    }
    for (uint i = 0; i < accessors.length; i++) {
      require(accessorFunctions[accessors[i]] != address(0), "Dispatcher/SelectorNotSet");
      accessorFunctions[accessors[i]] = address(0);
      emit RouterSpecificFunctionRemoved(accessorFunctions[accessors[i]], accessors[i], false);
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
  function mutateRouterState(bytes4 selector, address reserveId, IERC20 token, bytes calldata data) external onlyBound {
    address router = mutatorFunctions[selector];
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

    address router = accessorFunctions[selector];
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
