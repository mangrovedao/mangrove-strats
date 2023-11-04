// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {Proxy} from "@openzepplin/contracts/proxy/proxy.sol";

///@title Mangrove Smart Router Proxy
contract SmartRouterProxy is AccessControlled(msg.sender), Proxy {
  SmartRouter public immutable IMPLEMENTATION;

  constructor(SmartRouter implementation) Proxy() {
    IMPLEMENTATION = implementation;
  }

  function _implementation() internal override returns (address) {
    return address(IMPLEMENTATION);
  }
}
