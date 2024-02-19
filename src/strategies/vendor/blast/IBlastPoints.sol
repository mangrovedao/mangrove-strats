// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface IBlastPoints {
  /// @notice Returns the address of the admin of the BlastPoints contract
  /// @return The address of the admin of the BlastPoints contract
  function blastPointsAdmin() external view returns (address);
}
