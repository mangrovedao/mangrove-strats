// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum YieldMode {
  AUTOMATIC,
  VOID,
  CLAIMABLE
}

interface IERC20Rebasing {
  // changes the yield mode of the caller and update the balance
  // to reflect the configuration
  function configure(YieldMode) external returns (uint);
  // "claimable" yield mode accounts can call this this claim their yield
  // to another address
  function claim(address recipient, uint amount) external returns (uint);
  // read the claimable amount for an account
  function getClaimableAmount(address account) external view returns (uint);
}
