// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPool} from "./IPool.sol";

interface IFactory {
  function getPool(uint _poolId) external view returns (IPool);
  function router() external view returns (address);
}
