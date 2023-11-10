// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "./abstract/AbstractRouter.sol";

///@title Mangrove Smart Router storage (randomized access)
library SmartRouterStorage {
  bytes32 private constant OFFSET = keccak256("MangroveStrats.SmartRouterStorage.Layout");

  ///@notice Storage layout
  ///@param routeLogics logics approved by admin in order to pull/push liquidity in an offer specific manner
  struct Layout {
    mapping(IERC20 token => mapping(bytes32 olKeyHash => mapping(uint offerId => AbstractRouter logic))) routeLogics;
  }

  function getStorage() internal pure returns (Layout storage st) {
    bytes32 offset = OFFSET;
    assembly ("memory-safe") {
      st.slot := offset
    }
  }

  /**
   * @notice intermediate function to allow a call to be delagated to IMPLEMENTATION while preserving the a `view` attribute.
   * @dev scheme is as follows: for some `view` function `f` of IMPLEMENTATION, one does `staticcall(_staticdelegatecall(f))` which will retain for the `view` attribute
   */
  function _staticdelegatecall(address impl, bytes calldata data) external {
    require(msg.sender == address(this), "SmartRouterStorage/internalOnly");
    (bool success, bytes memory retdata) = impl.delegatecall(data);
    if (!success) {
      revertWithData(retdata);
    }
    assembly ("memory-safe") {
      return(add(retdata, 32), returndatasize())
    }
  }

  ///@notice propagates revert occurring during a delegatecall
  ///@param retdata the return data of the delegatecall
  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("SmartRouter/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }
}
