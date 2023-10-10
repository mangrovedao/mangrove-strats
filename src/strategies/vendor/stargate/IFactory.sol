// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPool} from "./IPool.sol";

interface IFactory {
  function getPool(uint256 _poolId) external view returns (IPool);
  function allPools() external view returns (address[] memory);
}