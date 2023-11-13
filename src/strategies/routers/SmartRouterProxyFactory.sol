// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {SmartRouterProxy, SmartRouter} from "./SmartRouterProxy.sol";

/// @title Mangrove Smart Router Proxy Factory
/// @notice Factory contract for the deployment of SmartRouterProxy instances using CREATE2 for deterministic addresses.
/// @dev Utilizes Ethereum's CREATE2 opcode for deploying contracts with predictable addresses.
contract SmartRouterProxyFactory {
  /// @notice The immutable SmartRouter implementation address which all proxies deployed by this factory will use.
  SmartRouter public immutable ROUTER_IMPLEMENTATION;

  /// @notice Emitted when a new proxy is deployed through this factory.
  /// @param owner The address which will be the admin of the newly deployed proxy.
  /// @param implementation The address of the SmartRouter implementation used by the proxy.
  event ProxyDeployed(address indexed owner, address indexed implementation);

  /// @notice Initializes the factory with the specified SmartRouter implementation.
  /// @param implementation The SmartRouter contract address to be used as the implementation for all proxies created by this factory.
  constructor(SmartRouter implementation) {
    ROUTER_IMPLEMENTATION = implementation;
  }

  /// @notice Computes the deterministic address of a proxy deployed for a specific owner using CREATE2.
  /// @param owner The prospective admin and owner of the new proxy contract.
  /// @return The address where the proxy will be deployed.
  /// @dev The computed address is determined by the owner's address and the factory's address
  function computeProxyAddress(address owner) public view returns (address payable) {
    bytes memory creationCode = type(SmartRouterProxy).creationCode;
    bytes memory args = abi.encode(ROUTER_IMPLEMENTATION);
    bytes32 initcodeHash = keccak256(abi.encodePacked(creationCode, args));
    bytes32 salt = keccak256(abi.encode(owner));
    return _extractAddress(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)));
  }

  /// @notice Converts a padded bytes32 value to a payable address.
  /// @param zeroPaddedAddress The bytes32 value representing an address with padding.
  /// @return The corresponding payable address.
  function _extractAddress(bytes32 zeroPaddedAddress) private pure returns (address payable) {
    return payable(address(uint160(uint(zeroPaddedAddress))));
  }

  /// @notice Deploys a new SmartRouterProxy for a given owner and binds it to this factory.
  /// @param owner The address to be set as the admin and initial owner of the proxy.
  /// @return proxy The address of the newly deployed SmartRouterProxy.
  /// @dev Emits a ProxyDeployed event upon successful deployment.
  ///      Note that the deployment can be initiated by any caller, on behalf of `owner`.
  function deployRouter(address owner) public returns (SmartRouter proxy) {
    proxy = SmartRouter(address(new SmartRouterProxy{salt:keccak256(abi.encode(owner))}(ROUTER_IMPLEMENTATION)));
    SmartRouter(address(proxy)).bind(address(this));
    emit ProxyDeployed(owner, address(ROUTER_IMPLEMENTATION));
  }

  /// @notice Deploys a SmartRouterProxy for a given owner if one has not already been deployed.
  /// @param owner The address to be set as the admin and initial owner of the proxy.
  /// @return proxy The address of the SmartRouterProxy.
  /// @return created A boolean indicating if the proxy was created during this call.
  /// @dev If the proxy already exists at the computed address, the function will not redeploy it.
  ///      The `created` return value indicates whether the proxy was created as a result of this call.
  function deployRouterIfNeeded(address owner) public returns (SmartRouter proxy, bool created) {
    proxy = SmartRouter(computeProxyAddress(owner));
    if (address(proxy).code.length == 0) {
      require(deployRouter(owner) == proxy, "Deployed via create2 failed");
      created = true;
    }
  }
}
