// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {IERC20} from "@mgv/lib/IERC20.sol";

interface IPool is IERC20 {
  function poolId() external view returns (uint16);

  function token() external view returns (address);

  function totalLiquidity() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function convertRate() external view returns (uint256);

  function amountLPtoLD(uint256 _amountLP) external view returns (uint256);
}
