// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";

import {OrbitSpaceStation} from "@orbit-protocol/contracts/SpaceStation.sol";
import {OrbitPriceOracle} from "./OrbitPriceOracle.sol";
import {OErc20} from "@orbit-protocol/contracts/OErc20.sol";
import {OErc20Delegator} from "@orbit-protocol/contracts/Core/CErc20Delegator.sol";
import {OErc20Delegate} from "@orbit-protocol/contracts/Core/CErc20Delegate.sol";

import {IERC20} from "@mgv/lib/IERC20.sol";
import {JumpRateModelV2} from "@orbit-protocol/contracts/InterestRate/JumpRateModelV2.sol";
import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";
import {Blast} from "@mgv/src/toy/blast/Blast.sol";
import {OToken} from "@orbit-protocol/contracts/OToken.sol";

contract OrbitFork is BlastSepoliaFork {
  OrbitSpaceStation public spaceStation;

  constructor() {
    // BLOCK_NUMBER = 0;
    spaceStation = OrbitSpaceStation(0xac841600ea0FfE66CEbbFc601D60783D8fb54B94);
  }
}
