// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {Proxy} from "@openzeppelin/contracts/proxy/proxy.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {SmartRouter} from "./SmartRouter.sol";

///@title Mangrove Smart Router Proxy
contract SmartRouterProxy is AccessControlled(msg.sender), Proxy {
  SmartRouter public immutable IMPLEMENTATION;

  constructor(SmartRouter implementation) Proxy() {
    IMPLEMENTATION = implementation;
  }

  receive() external payable virtual {}

  ///@inheritdoc Proxy
  function _implementation() internal view override returns (address) {
    return address(IMPLEMENTATION);
  }
}
