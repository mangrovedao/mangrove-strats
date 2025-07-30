// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CompoundV2Router, ICToken, IERC20, InterestRateModel} from "./CompoundV2Router.sol";

/// @dev Takara Lend cTokens use timestamp instead of block number for fee accrual
interface ITToken is ICToken {
  function accrualBlockTimestamp() external view returns (uint);
  function getCash() external view returns (uint);
}

interface IComptroller {
  function claimReward(address[] memory holders, address tokens) external;
}

/// @dev Special {CompoundV2Router} implementation for Takara Lend, where
/// some of the original code was modified
contract TakaraLendRouter is CompoundV2Router {
  /// @notice The Comptroller contract
  IComptroller public immutable TAKARA_COMPTROLLER;

  constructor(IComptroller comptroller) {
    TAKARA_COMPTROLLER = comptroller;
  }

  /// @notice Claims rewards for the base and quote tokens
  /// @dev Only callable by the admin
  function claimReward(address token) public {
    address[] memory holders = new address[](1);
    holders[0] = address(this);
    TAKARA_COMPTROLLER.claimReward(holders, token);
  }

  /// @inheritdoc CompoundV2Router
  function _readCTokenState(ICToken cToken) internal view override returns (InterestCache memory cache) {
    cache.accrualBlock = ITToken(address(cToken)).accrualBlockTimestamp();
    cache.cashPrior = ITToken(address(cToken)).getCash();
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

    // Read current state
    cache = _readCTokenState(cToken);

    // Short-circuit accumulating 0 interest
    if (cache.accrualBlock == currentBlockTimestamp) {
      return;
    }

    // Calculate the number of blocks elapsed since the last accrual
    uint blockDelta = currentBlockTimestamp - cache.accrualBlock;

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
