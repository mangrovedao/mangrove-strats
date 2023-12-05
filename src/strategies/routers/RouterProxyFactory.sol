// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {RouterProxy, AbstractRouter} from "./RouterProxy.sol";

/// @title Mangrove Router Proxy Factory
/// @notice Factory contract for the deployment of RouterProxy instances using CREATE2 for deterministic addresses.
/// @dev Utilizes Ethereum's CREATE2 opcode for deploying contracts with predictable addresses.
contract RouterProxyFactory {
  /// @notice Emitted when a new proxy is deployed through this factory.
  /// @param proxy the deployed proxy contract
  /// @param owner The address which will be the admin and immutable owner of the newly deployed proxy.
  /// @param implementation The address of the router implementation used by the proxy.
  event ProxyDeployed(RouterProxy proxy, address indexed owner, AbstractRouter indexed implementation);

  /// @notice Computes the deterministic address of a proxy deployed for a specific owner using CREATE2.
  /// @param owner The prospective admin and owner of the new proxy contract.
  /// @param routerImplementation router contract which implements routing functions
  /// @return The address where the proxy will be deployed.
  /// @dev The computed address is determined by the owner's address and the factory's address
  function computeProxyAddress(address owner, AbstractRouter routerImplementation)
    public
    view
    returns (address payable)
  {
    bytes memory creationCode = type(RouterProxy).creationCode;
    bytes memory args = abi.encode(routerImplementation);
    bytes32 initcodeHash = keccak256(abi.encodePacked(creationCode, args));
    bytes32 salt = keccak256(abi.encode(owner));
    return _extractAddress(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)));
  }

  /// @notice Converts a padded bytes32 value to a payable address.
  /// @param zeroPaddedAddress The bytes32 value representing an address with padding.
  /// @return res The corresponding payable address.
  function _extractAddress(bytes32 zeroPaddedAddress) private pure returns (address payable res) {
    assembly {
      res := zeroPaddedAddress
    }
  }

  /// @notice Deploys a new RouterProxy for a given owner.
  /// @param owner The address to be set as initial admin and immutable owner of the proxy.
  /// @param routerImplementation router contract which implements routing functions
  /// @return proxy The address of the newly deployed RouterProxy.
  /// @dev Emits a ProxyDeployed event upon successful deployment.
  ///      Note that the deployment can be initiated by any caller, on behalf of `owner`.
  function deployProxy(address owner, AbstractRouter routerImplementation) public returns (RouterProxy proxy) {
    proxy = new RouterProxy{salt:keccak256(abi.encode(owner))}(routerImplementation);
    // TODO: The access controlled admin must maybe be immutable (or this is a vector attack)
    // We will always link one user with a router address anyway
    AbstractRouter(address(proxy)).setAdmin(owner);
    emit ProxyDeployed(proxy, owner, routerImplementation);
  }

  /// @notice Deploys a RouterProxy for a given owner if one has not already been deployed.
  /// @param owner The address to be set as initial admin and immutable owner of the proxy.
  /// @param routerImplementation router contract which implements routing functions
  /// @return proxy The address of the RouterProxy.
  /// @return created A boolean indicating if the proxy was created during this call.
  /// @dev If the proxy already exists at the computed address, the function will not redeploy it.
  ///      The `created` return value indicates whether the proxy was created as a result of this call.
  function instantiate(address owner, AbstractRouter routerImplementation)
    public
    returns (RouterProxy proxy, bool created)
  {
    proxy = RouterProxy(computeProxyAddress(owner, routerImplementation));
    if (address(proxy).code.length == 0) {
      require(deployProxy(owner, routerImplementation) == proxy, "Deployed via create2 failed");
      created = true;
    }
  }

  /**
   * The custom bytecode for the proxy will be as follows:
   *
   * init code (or constructor) of the proxy
   * // store the caller address to slot 0
   * [00] CALLER
   * [01] RETURNDATASIZE // pushes a 0 to the stack
   * [02] SSTORE
   *
   * [03] RETURNDATASIZE // pushes a 0 to the stack
   * [04-05] PUSH1 2d size of contract code (in bytes, without init code)
   * [06] DUP1
   *
   * [07-08] PUSH1 0d // start line of contract code (in bytes)
   * [09] RETURNDATASIZE // pushes a 0 to the stack
   *
   * [0a] CODECOPY // copies the code with size from [06], from offset [08] to destination offset [0a] (i.e. 0)
   * [0b] DUP2 // copies the 0 from stack to top
   * [0c] RETURN // with args: size from [05] and offset as 0 from [09]
   *
   * // contract code
   * // copy the transaction calldata to memory
   * [0d] CALLDATASIZE // pushes the size of the calldata to the stack
   * [0e] RETURNDATASIZE // pushes a 0 to the stack
   * [0f] RETURNDATASIZE // pushes a 0 to the stack
   * [10] CALLDATACOPY // copies the calldata to memory with size from [0d] and offset 0 and destination offset from 0
   * // Thus copying the calldata to slot 0 in memory
   *
   * // preparing for delegatecall
   * [11] RETURNDATASIZE // pushes a 0 to the stack (utils that will be used later)
   * [12] RETURNDATASIZE // 0 for return size to copy
   * [13] RETURNDATASIZE // 0 for return offset
   * [14] CALLDATASIZE // pushes the size of the calldata to the stack
   * [15] RETURNDATASIZE // 0 for args offset
   * [16-2a] PUSH20 address of router implementation (1 byte for PUSH20 and 20 bytes for address from 18 to 2b)
   * [2b] GAS // pushes the gas remaining to the stack
   *
   * // delegatecall
   * [2c] DELEGATECALL // calls the router implementation with the calldata from slot 0 in memory
   * // pushes 01 or 00 to the stack depending on success or failure
   *
   * // copy return data to memory
   * [2d] RETURNDATASIZE // return data size to the stack
   * [2e] DUP3 // copies the 0 from before [11] to the stack
   * [2f] DUP1 // copies the 0 from [2e] to the stack
   * [30] RETURNDATACOPY // copies from offset 0 to destination offset 0 with size from [2f]
   *
   * // prepare conditional jump for revert or return
   * [31] SWAP1 // swaps a 0 for delegatecall success result
   *            // now stack has delegatecall success result at the bottom and 00 on top
   * [32] RETURNDATASIZE // pushes the return data size to the stack
   * [33] SWAP2 // swaps the return data size with the delegatecall success result
   *            // now stack has return data size at the bottom, 00 above, and delegatecall success result on top
   * [34-35] PUSH1 43 // counter to jump to (in bytes from start of contract code)
   * [36] JUMPI // jumps to counter at [35] if delegatecall success result is 01 else continues
   * [37] REVERT // reverts with return data from slot 0 in memory with size from [32]
   * [38] JUMPDEST // jump destination for [35]
   * [39] RETURN // returns with return data from slot 0 in memory with size from [32]
   *
   *
   * @param routerImplementation implementation of the router
   * @return code of the router implementation
   */
  // function getBytecodeFor(address routerImplementation) public pure returns (bytes memory code) {

  // }
}
