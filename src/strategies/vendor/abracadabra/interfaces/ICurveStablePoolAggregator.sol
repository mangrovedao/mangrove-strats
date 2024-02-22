// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IAggregator} from "./IAggregator.sol";

interface ICurveStablePoolAggregator is IAggregator {
    function curvePool() external view returns (address);
}
