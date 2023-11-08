// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {SmartRouterProxy, SmartRouter} from "./SmartRouterProxy.sol";

///@title Mangrove Smart Router deployment functions
///@dev mostly taken from "forge-std/StdUtils.sol"
contract SmartRouterProxyFactory {
  SmartRouter public immutable IMPLEMENTATION;

  event ProxyDeployed(address indexed owner, address indexed implementation);

  constructor(SmartRouter implementation) {
    IMPLEMENTATION = implementation;
  }

  /// @notice returns the address of the proxy that would be deployed with CREATE2
  /// @param owner the owner of the proxy contract
  function computeProxyAddress(address owner) public view returns (address payable) {
    bytes memory creationCode = type(SmartRouterProxy).creationCode;
    bytes memory args = abi.encode(IMPLEMENTATION);
    bytes32 initcodeHash = keccak256(abi.encodePacked(creationCode, args));
    bytes32 salt = keccak256(abi.encode(owner));
    return extractAddress(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)));
  }

  ///@notice removes left 0 padding of an address into a bytes32
  ///@param zeroPaddedAddress the 0 padded address obtained as a result of hash(0xFF, deployer, salt, deployCode)
  ///@return address corresponding to `bytesValue`
  function extractAddress(bytes32 zeroPaddedAddress) private pure returns (address payable) {
    return payable(address(uint160(uint(zeroPaddedAddress))));
  }

  ///@notice Proxy deployer
  ///@param owner the address to be used for proxy owner
  function deploy(address owner) public returns (SmartRouterProxy proxy) {
    proxy = new SmartRouterProxy{salt:keccak256(abi.encode(owner))}(IMPLEMENTATION);
    proxy.setAdmin(owner);
    emit ProxyDeployed(owner, address(IMPLEMENTATION));
  }

  ///@notice Proxy deployer if not already deployed
  ///@param owner the address to be used for proxy owner
  function deployIfNeeded(address owner) public returns (SmartRouterProxy proxy, bool created) {
    proxy = SmartRouterProxy(computeProxyAddress(owner));
    if (address(proxy).code.length == 0) {
      require(deploy(owner) == proxy, "Deployed via create2 failed");
      created = true;
    }
  }
}
