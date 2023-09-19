// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MultiRouter, MonoRouter, AbstractRouter} from "../abstract/MultiRouter.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {ViewDelegator, IViewDelegator} from "../../utils/ViewDelegator.sol";

contract Dispatcher is MultiRouter, ViewDelegator {
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

  /// @notice Safely calls a router contract
  /// @dev This will revert if the router contract does not exist or if the call fails
  /// @param router The MonoRouter contract to call
  /// @param data The data to send to the router contract (encoded with abi.encodeWithSelector(...))
  /// @return returndata The data returned by the router contract
  function _safeRouterDelegateCall(MonoRouter router, bytes memory data) internal returns (bytes memory returndata) {
    (bool success, bytes memory _returndata) = address(router).delegatecall(data);

    if (success == false) {
      if (_returndata.length > 0) {
        assembly {
          let returndata_size := mload(_returndata)
          revert(add(32, _returndata), returndata_size)
        }
      } else {
        revert("Dispatcher/DelegateCallFailed");
      }
    } else {
      returndata = _returndata;
    }
  }

  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint pulled)
  {
    MonoRouter router = _getRouterSafely(token, reserveId);
    bytes memory returnData =
      _safeRouterDelegateCall(router, abi.encodeWithSelector(router.pull.selector, token, reserveId, amount, strict));
    pulled = abi.decode(returnData, (uint));
  }

  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint pushed) {
    MonoRouter router = _getRouterSafely(token, reserveId);
    bytes memory returnData =
      _safeRouterDelegateCall(router, abi.encodeWithSelector(router.push.selector, token, reserveId, amount));
    pushed = abi.decode(returnData, (uint));
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
}
