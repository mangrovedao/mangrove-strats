// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {RouterProxy, AbstractRouter} from "./RouterProxy.sol";

/// @title Mangrove Router Proxy Factory
/// @notice Factory contract for the deployment of RouterProxy instances using CREATE2 for deterministic addresses.
/// @dev Utilizes Ethereum's CREATE2 opcode for deploying contracts with predictable addresses.
contract RouterProxyFactory {
  /// @notice Emitted when a new proxy is deployed through this factory.
  /// @param owner The address which will be the admin and immutable owner of the newly deployed proxy.
  /// @param implementation The address of the router implementation used by the proxy.
  event ProxyDeployed(RouterProxy proxy, address indexed owner, AbstractRouter indexed implementation);

  /// @notice Computes the deterministic address of a proxy deployed for a specific owner using CREATE2.
  /// @param owner The prospective admin and owner of the new proxy contract.
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
  /// @return The corresponding payable address.
  function _extractAddress(bytes32 zeroPaddedAddress) private pure returns (address payable) {
    return payable(address(uint160(uint(zeroPaddedAddress))));
  }

  /// @notice Deploys a new RouterProxy for a given owner and binds it to msg.sender.
  /// @param owner The address to be set as initial admin and immutable owner of the proxy.
  /// @return proxy The address of the newly deployed RouterProxy.
  /// @dev Emits a ProxyDeployed event upon successful deployment.
  ///      Note that the deployment can be initiated by any caller, on behalf of `owner`.
  function deployProxy(address owner, AbstractRouter routerImplementation) public returns (RouterProxy proxy) {
    proxy = new RouterProxy{salt:keccak256(abi.encode(owner))}(routerImplementation);
    AbstractRouter(address(proxy)).bind(msg.sender);
    // sets the admin *after* binding this contract to the router
    AbstractRouter(address(proxy)).setAdmin(owner);
    emit ProxyDeployed(proxy, owner, routerImplementation);
  }

  /// @notice Deploys a RouterProxy for a given owner if one has not already been deployed.
  /// @param owner The address to be set as initial admin and immutable owner of the proxy.
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
}
