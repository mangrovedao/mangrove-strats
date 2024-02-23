// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ContractDeployer {
  function deployFromBytecode(bytes memory bytecode) public returns (address result) {
    assembly {
      let size := mload(bytecode)
      let data := add(bytecode, 0x20)
      result := create(0, data, size)
      if iszero(result) { revert(0, 0) }
    }
  }

  function deployBytecodeWithArgs(bytes memory bytecode, bytes memory args) public returns (address result) {
    bytes memory data = abi.encodePacked(bytecode, args);
    result = deployFromBytecode(data);
  }
}
