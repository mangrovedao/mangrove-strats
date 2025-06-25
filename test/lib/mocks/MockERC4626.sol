// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockERC4626
/// @notice A mock ERC4626 vault that implements reward vesting to simulate yield growth over time
/// @dev This contract allows adding rewards that vest linearly over a specified duration
contract MockERC4626 is ERC4626, Ownable {
  using Math for uint;

  /// @notice Reward vesting configuration
  struct RewardPeriod {
    uint totalReward; // Total reward tokens to vest
    uint startTime; // When vesting starts
    uint duration; // Duration of vesting in seconds
    uint claimedAmount; // Amount already claimed/vested
  }

  /// @notice Array of all reward periods
  RewardPeriod[] public rewardPeriods;

  /// @notice The total amount of rewards that have been added but not yet fully vested
  uint public totalPendingRewards;

  /// @notice The total amount of rewards that have been vested and added to totalAssets
  uint public totalVestedRewards;

  /// @notice Emitted when new rewards are added
  event RewardsAdded(uint indexed periodId, uint amount, uint duration);

  /// @notice Emitted when rewards are vested
  event RewardsVested(uint indexed periodId, uint amount);

  /// @notice Emitted when rewards are manually distributed
  event RewardsDistributed(uint amount);

  /// @notice Constructor
  /// @param asset_ The underlying asset (ERC20 token)
  /// @param name_ The name of the vault token
  /// @param symbol_ The symbol of the vault token
  constructor(IERC20 asset_, string memory name_, string memory symbol_)
    ERC4626(asset_)
    ERC20(name_, symbol_)
    Ownable(msg.sender)
  {}

  /// @notice Add rewards to be vested over a specific duration
  /// @param amount The amount of reward tokens to add
  /// @param duration The vesting duration in seconds
  /// @dev The caller must transfer the reward tokens to this contract before calling this function
  function addRewards(uint amount, uint duration) external onlyOwner {
    require(amount > 0, "Amount must be greater than 0");
    require(duration > 0, "Duration must be greater than 0");

    // Transfer reward tokens from caller to this contract
    IERC20(asset()).transferFrom(msg.sender, address(this), amount);

    // Create new reward period
    rewardPeriods.push(
      RewardPeriod({totalReward: amount, startTime: block.timestamp, duration: duration, claimedAmount: 0})
    );

    totalPendingRewards += amount;

    emit RewardsAdded(rewardPeriods.length - 1, amount, duration);
  }

  /// @notice Vest all available rewards across all periods
  /// @return totalVested The total amount of rewards vested
  function vestRewards() public returns (uint totalVested) {
    uint currentTime = block.timestamp;

    for (uint i = 0; i < rewardPeriods.length; i++) {
      RewardPeriod storage period = rewardPeriods[i];

      if (period.claimedAmount >= period.totalReward) {
        continue; // Period fully vested
      }

      uint vestedAmount = _calculateVestedAmount(period, currentTime);
      uint newVested = vestedAmount - period.claimedAmount;

      if (newVested > 0) {
        period.claimedAmount = vestedAmount;
        totalVested += newVested;

        emit RewardsVested(i, newVested);
      }
    }

    if (totalVested > 0) {
      totalPendingRewards -= totalVested;
      totalVestedRewards += totalVested;
    }
  }

  /// @notice Calculate vested amount for a specific reward period
  /// @param period The reward period
  /// @param currentTime The current timestamp
  /// @return vestedAmount The amount that has vested
  function _calculateVestedAmount(RewardPeriod memory period, uint currentTime)
    internal
    pure
    returns (uint vestedAmount)
  {
    if (currentTime <= period.startTime) {
      return 0;
    }

    uint elapsedTime = currentTime - period.startTime;

    if (elapsedTime >= period.duration) {
      return period.totalReward;
    }

    return (period.totalReward * elapsedTime) / period.duration;
  }

  /// @notice Get pending rewards (not yet vested)
  /// @return pending The total amount of pending rewards
  function getPendingRewards() external view returns (uint pending) {
    uint currentTime = block.timestamp;
    uint totalVestable = 0;

    for (uint i = 0; i < rewardPeriods.length; i++) {
      RewardPeriod memory period = rewardPeriods[i];
      uint vestedAmount = _calculateVestedAmount(period, currentTime);
      totalVestable += (vestedAmount - period.claimedAmount);
    }

    return totalVestable;
  }

  /// @notice Get the number of reward periods
  /// @return count The number of reward periods
  function getRewardPeriodsCount() external view returns (uint count) {
    return rewardPeriods.length;
  }

  /// @notice Get reward period information
  /// @param periodId The reward period ID
  /// @return period The reward period struct
  function getRewardPeriod(uint periodId) external view returns (RewardPeriod memory period) {
    require(periodId < rewardPeriods.length, "Invalid period ID");
    return rewardPeriods[periodId];
  }

  /// @notice Override totalAssets to include vested rewards
  /// @return assets The total assets including vested rewards
  function totalAssets() public view override returns (uint assets) {
    // Get base asset balance
    uint baseAssets = IERC20(asset()).balanceOf(address(this));

    // Calculate currently vestable rewards (not yet claimed)
    uint currentTime = block.timestamp;
    uint pendingVested = 0;

    for (uint i = 0; i < rewardPeriods.length; i++) {
      RewardPeriod memory period = rewardPeriods[i];
      uint vestedAmount = _calculateVestedAmount(period, currentTime);
      pendingVested += (vestedAmount - period.claimedAmount);
    }

    // Total assets = base balance - pending rewards + already vested rewards
    return baseAssets - totalPendingRewards + pendingVested + totalVestedRewards;
  }

  /// @notice Manually distribute rewards immediately (for testing)
  /// @param amount The amount to distribute immediately
  function distributeRewardsNow(uint amount) external onlyOwner {
    require(amount > 0, "Amount must be greater than 0");

    // Transfer reward tokens from caller to this contract
    IERC20(asset()).transferFrom(msg.sender, address(this), amount);

    // Add directly to vested rewards
    totalVestedRewards += amount;

    emit RewardsDistributed(amount);
  }

  /// @notice Emergency function to claim all rewards immediately
  /// @dev Only for testing purposes
  function emergencyVestAll() external onlyOwner {
    for (uint i = 0; i < rewardPeriods.length; i++) {
      RewardPeriod storage period = rewardPeriods[i];
      uint remaining = period.totalReward - period.claimedAmount;
      if (remaining > 0) {
        period.claimedAmount = period.totalReward;
        totalVestedRewards += remaining;
        totalPendingRewards -= remaining;
      }
    }
  }

  /// @notice Get vault statistics
  /// @return totalAssets_ Current total assets
  /// @return totalPending Total pending rewards
  /// @return totalVested Total vested rewards
  /// @return totalSupply_ Total supply of shares
  function getVaultStats()
    external
    view
    returns (uint totalAssets_, uint totalPending, uint totalVested, uint totalSupply_)
  {
    return (totalAssets(), totalPendingRewards, totalVestedRewards, totalSupply());
  }
}
