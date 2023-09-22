// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MultiRouter, MonoRouter, AbstractRouter} from "../abstract/MultiRouter.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IViewDelegator} from "../../utils/ViewDelegator.sol";

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
  function initializeRouter(address router, bytes4[] calldata selectors) external onlyAdmin {
    for (uint i = 0; i < selectors.length; i++) {
      require(routerSpecificFunctions[selectors[i]] == address(0), "Dispatcher/SelectorAlreadySet");
      routerSpecificFunctions[selectors[i]] = router;
      emit RouterSpecificFunctionAdded(router, selectors[i]);
    }
  }

  /// @notice Removes a router contract by removing the router specific functions
  /// @dev if a selector is not set, it will revert
  /// @param selectors The selectors to remove
  function removeFunctions(bytes4[] calldata selectors) external onlyAdmin {
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
  function __push__(IERC20 token, address reserveId, uint) internal virtual override returns (uint pushed) {
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
  function __checkList__(IERC20 token, address reserveId) internal view virtual override {
    MonoRouter router = _getRouterSafely(token, reserveId);
    IViewDelegator(address(this)).staticdelegatecall(
      address(router), abi.encodeWithSelector(router.checkList.selector, token, reserveId)
    );
  }

  /// @inheritdoc	AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    return token.balanceOf(reserveId);
  }

  fallback() external {
    if (msg.sig == IViewDelegator.staticdelegatecall.selector) {
      (, address target, bytes memory data) = abi.decode(msg.data, (bytes4, address, bytes));
      assembly {
        let result := delegatecall(gas(), target, add(data, 0x20), mload(data), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
      }
    } else {
      address router = routerSpecificFunctions[msg.sig];
      require(router != address(0), "Dispatcher/SelectorNotSet");

      assembly {
        calldatacopy(0, 0, calldatasize())
        let result := delegatecall(gas(), router, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
      }
    }
  }

  function setMaxBudffer(address r, IERC20) external onlyCaller(r) {}
}