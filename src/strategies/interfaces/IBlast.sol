// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface IBlast {
  // Note: the full interface for IBlast can be found below
  function configureClaimableGas() external;
  function configureGovernor(address governor) external;
}
