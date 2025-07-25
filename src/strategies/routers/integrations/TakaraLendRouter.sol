// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CompoundV2Router, ICToken, IERC20, InterestRateModel} from "./CompoundV2Router.sol";

/// @dev Takara Lend cTokens use timestamp instead of block number for fee accrual
interface ITToken is ICToken {
  function accrualBlockTimestamp() external view returns (uint);
}

/// @dev Special {CompoundV2Router} implementation for Takara Lend, where
/// some of the original code was modified
contract TakaraLendRouter is CompoundV2Router {
  /// @inheritdoc CompoundV2Router
  function _readCTokenState(ICToken cToken) internal view override returns (InterestCache memory cache) {
    cache.accrualBlock = ITToken(address(cToken)).accrualBlockTimestamp();
    cache.cashPrior = IERC20(cToken.underlying()).balanceOf(address(cToken));
    cache.totalBorrows = cToken.totalBorrows();
    cache.totalReserves = cToken.totalReserves();
    cache.borrowIndex = cToken.borrowIndex();
  }

  /// @inheritdoc CompoundV2Router
  function _calculateNewInterestValues(ICToken cToken, InterestCache memory cache, uint blockDelta)
    internal
    view
    override
    returns (uint newTotalBorrows, uint newTotalReserves, uint newBorrowIndex)
  {
    InterestRateModel interestRateModel = cToken.interestRateModel();

    // Calculate the current borrow interest rate
    uint borrowRateMantissa = interestRateModel.getBorrowRate(cache.cashPrior, cache.totalBorrows, cache.totalReserves);
    require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

    // Calculate simple interest factor and accumulated interest
    Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
    uint interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, cache.totalBorrows);

    // Calculate new values
    newTotalBorrows = interestAccumulated + cache.totalBorrows;
    newTotalReserves = mul_ScalarTruncateAddUInt(
      Exp({mantissa: cToken.reserveFactorMantissa()}), interestAccumulated, cache.totalReserves
    );
    newBorrowIndex = mul_ScalarTruncateAddUInt(simpleInterestFactor, cache.borrowIndex, cache.borrowIndex);
  }

  /// @inheritdoc CompoundV2Router
  function _accrueInterest(ICToken cToken, InterestCache memory cache) internal view override {
    uint currentBlockTimestamp = block.timestamp;
    uint accrualBlockTimestampPrior = ITToken(address(cToken)).accrualBlockTimestamp();

    // Short-circuit accumulating 0 interest
    if (accrualBlockTimestampPrior == currentBlockTimestamp) {
      return;
    }

    // Read current state
    cache = _readCTokenState(cToken);

    // Calculate the number of blocks elapsed since the last accrual
    uint blockDelta = currentBlockTimestamp - accrualBlockTimestampPrior;

    // Calculate new interest values
    (uint newTotalBorrows, uint newTotalReserves, uint newBorrowIndex) =
      _calculateNewInterestValues(cToken, cache, blockDelta);

    // Update cache with new values
    cache.accrualBlock = currentBlockTimestamp;
    cache.borrowIndex = newBorrowIndex;
    cache.totalBorrows = newTotalBorrows;
    cache.totalReserves = newTotalReserves;
  }
}
