// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {SmartRouterProxy, SmartRouter} from "./SmartRouterProxy.sol";

///@title Mangrove Smart Router lib
///@dev adapted from forge-std/StdUtils.sol
library SmartRouterLib {
  /// @dev returns the address of a contract created with CREATE2 by `deployer`
  function computeProxyAddress(SmartRouter smartRouter, address owner, address deployer)
    private
    pure
    returns (address payable)
  {
    bytes memory creationCode = type(SmartRouterProxy).creationCode;
    bytes memory args = abi.encode(smartRouter);
    bytes32 initcodeHash = keccak256(abi.encodePacked(creationCode, args));
    bytes32 salt = keccak256(abi.encode(owner));
    return payable(addressFromLast20Bytes(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash))));
  }

  function addressFromLast20Bytes(bytes32 bytesValue) private pure returns (address) {
    return address(uint160(uint(bytesValue)));
  }

  function deploy(SmartRouter smartRouter, address owner) internal returns (SmartRouterProxy proxy) {
    proxy = new SmartRouterProxy{salt:keccak256(abi.encode(owner))}(smartRouter);
    proxy.setAdmin(owner);
  }

  function deployIfNeeded(SmartRouter smartRouter, address owner) internal returns (SmartRouterProxy proxy) {
    proxy = SmartRouterProxy(computeProxyAddress(smartRouter, owner, address(this)));
    try proxy.admin() returns (address admin) {
      require(owner == admin, "SmartRouterLib/InconsistentAdmin");
    } catch {
      return deploy(smartRouter, owner);
    }
  }
}
