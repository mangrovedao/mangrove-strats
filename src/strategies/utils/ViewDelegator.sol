// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

interface IViewDelegator {
  function staticdelegatecall(address target, bytes memory data) external view returns (bytes memory);
}

contract ViewDelegator {
  fallback() external {
    if (msg.sig == IViewDelegator.staticdelegatecall.selector) {
      (address target, bytes memory data) = abi.decode(msg.data, (address, bytes));
      (bool success, bytes memory result) = target.delegatecall(data);
      assembly {
        if eq(success, 0) { revert(add(result, 32), mload(result)) }
        return(add(result, 32), mload(result))
      }
    }
  }
}
