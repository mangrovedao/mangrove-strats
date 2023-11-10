// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {SmartRouterProxy, SmartRouter} from "./SmartRouterProxy.sol";

///@title Mangrove Smart Router deployment functions
///@dev mostly taken from "forge-std/StdUtils.sol"
contract SmartRouterProxyFactory {
  SmartRouter public immutable ROUTER_IMPLEMENTATION;

  event ProxyDeployed(address indexed owner, address indexed implementation);

  constructor(SmartRouter implementation) {
    ROUTER_IMPLEMENTATION = implementation;
  }

  /// @notice returns the address of the proxy that would be deployed with CREATE2
  /// @param owner the owner of the proxy contract
  function computeProxyAddress(address owner) public view returns (address payable) {
    bytes memory creationCode = type(SmartRouterProxy).creationCode;
    bytes memory args = abi.encode(ROUTER_IMPLEMENTATION);
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

  ///@notice Proxy deployer. Binds the proxy to the this contract and sets admin of the proxy to `owner`
  ///@param owner the address to be used for proxy owner
  ///@dev beware that anyone can call this function on behalf of owner. But `owner` will be admin.
  function deployRouter(address owner) public returns (SmartRouter proxy) {
    proxy = SmartRouter(address(new SmartRouterProxy{salt:keccak256(abi.encode(owner))}(ROUTER_IMPLEMENTATION)));
    SmartRouter(address(proxy)).bind(address(this));
    proxy.setAdmin(owner);
    emit ProxyDeployed(owner, address(ROUTER_IMPLEMENTATION));
  }

  ///@notice Proxy deployer if not already deployed
  ///@param owner the address to be used for proxy owner
  ///@dev beware that anyone can call this function on behalf of owner. But `owner` will be admin.
  function deployRouterIfNeeded(address owner) public returns (SmartRouter proxy, bool created) {
    proxy = SmartRouter(computeProxyAddress(owner));
    if (address(proxy).code.length == 0) {
      require(deployRouter(owner) == proxy, "Deployed via create2 failed");
      created = true;
    }
  }
}
