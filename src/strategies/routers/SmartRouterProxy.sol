// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {Proxy} from "@openzeppelin/contracts/proxy/proxy.sol";
import {SmartRouter} from "./SmartRouter.sol";

///@title Mangrove Smart Router Proxy
contract SmartRouterProxy is Proxy {
  SmartRouter public immutable IMPLEMENTATION;

  constructor(SmartRouter implementation) Proxy() {
    IMPLEMENTATION = implementation;
    // stores the caller address in storage slot 0x0 => this is the admin field
    assembly {
      sstore(0x0, caller())
    }
  }

  ///@inheritdoc Proxy
  function _implementation() internal view override returns (address) {
    return address(IMPLEMENTATION);
  }
}
