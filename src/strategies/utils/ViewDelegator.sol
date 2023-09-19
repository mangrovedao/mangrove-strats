// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

///@title `IViewDelegator` is a util interface to delegate static calls to a contract.
interface IViewDelegator {
  function staticdelegatecall(address target, bytes memory data) external view returns (bytes memory);
}

///@title `ViewDelegator` is a util contract to delegate static calls to a contract.
contract ViewDelegator {
  /// @notice Delegate a static call to a contract
  /// @dev This will revert if the call fails
  fallback() external {
    if (msg.sig == IViewDelegator.staticdelegatecall.selector) {
      (, address target, bytes memory data) = abi.decode(msg.data, (bytes4, address, bytes));
      (bool success, bytes memory result) = target.delegatecall(data);
      if (!success) {
        if (result.length > 0) {
          assembly {
            let returndata_size := mload(result)
            revert(add(32, result), returndata_size)
          }
        } else {
          revert("ViewDelegator/DelegateCallFailed");
        }
      }
      assembly {
        return(result, mload(result))
      }
    }
  }
}
