// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PriceOracle} from "@orbit-protocol/contracts/PriceOracle.sol";
import {OToken} from "@orbit-protocol/contracts/OToken.sol";

contract OrbitPriceOracle is PriceOracle {
  function getUnderlyingPrice(OToken) external view virtual override returns (uint) {
    return 1 ether;
  }
}
