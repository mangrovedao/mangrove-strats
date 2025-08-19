// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CompoundV2Router} from "./CompoundV2Router.sol";

interface ITakaraComptroller {
  function claimReward() external;
}

contract TakaraRouter is CompoundV2Router {
  ITakaraComptroller public immutable comptroller;

  constructor(ITakaraComptroller _comptroller) {
    comptroller = _comptroller;
  }

  function claimReward() external {
    comptroller.claimReward();
  }

  function _isAlternativeImplementation() internal view override returns (bool) {
    return true;
  }
}
