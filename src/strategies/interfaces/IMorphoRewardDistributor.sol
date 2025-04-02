// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

interface IMorphoRewardDistributor {
  function claim(address account, address reward, uint claimable, bytes32[] calldata proof)
    external
    returns (uint amount);
}
