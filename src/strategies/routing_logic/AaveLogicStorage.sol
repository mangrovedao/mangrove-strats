// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";

///@title Mangrove Smart Router storage (randomized access)
library AaveLogicStorage {
  bytes32 private constant OFFSET = keccak256("MangroveStrats.AaveLogicStorage.Layout");
  ///@notice Storage layout

  ///@notice routeLogics logics approved by admin in order to pull/push liquidity in an offer specific manner
  struct Layout {
    mapping(IERC20 token => uint8) credit_line_decrease;
  }

  function getStorage() internal pure returns (Layout storage st) {
    bytes32 offset = OFFSET;
    assembly ("memory-safe") {
      st.slot := offset
    }
  }

  ///@notice propagates revert occurring during a delegatecall
  ///@param retdata the return data of the delegatecall
  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("AaveLogic/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }
}
