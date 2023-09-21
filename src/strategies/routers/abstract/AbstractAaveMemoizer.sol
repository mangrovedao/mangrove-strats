// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {AaveV3Borrower} from "mgv_strat_src/strategies/integrations/AaveV3Borrower.sol";
import {DataTypes} from "mgv_strat_src/strategies/vendor/aave/v3/DataTypes.sol";
import {ReserveConfiguration} from "mgv_strat_src/strategies/vendor/aave/v3/ReserveConfiguration.sol";
import {ICreditDelegationToken} from "mgv_strat_src/strategies/vendor/aave/v3/ICreditDelegationToken.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow.
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
abstract contract AbstractAaveMemoizer is AaveV3Borrower {
  struct Account {
    uint collateral;
    uint debt;
    uint borrowPower;
    uint ltv;
    uint liquidationThreshold;
    uint health;
  }

  // structs to avoid stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  ///@param balanceOf the owner's balance of the token
  ///@param balanceOfMemoized whether the `balanceOf` has been memoized.
  ///@param overlyingBalanceOf the balance of the overlying.
  ///@param overlyingBalanceOfMemoized whether the `overlyingBalanceOf` has been memoized.
  ///@param reserveData the data pertaining to the asset
  ///@param reserveDataMemoized whether the `reserveData` has been memoized.
  ///@param debtBalanceOf amount of token borrowed by this contract
  ///@param debtBalanceOfMemoized wether `debtBalanceOf` is memoized
  ///@param data additional data that may be used by subsequent contracts
  struct Memoizer {
    uint balanceOf;
    bool balanceOfMemoized;
    uint overlyingBalanceOf;
    bool overlyingBalanceOfMemoized;
    DataTypes.ReserveData reserveData;
    bool reserveDataMemoized;
    uint debtBalanceOf;
    bool debtBalanceOfMemoized;
    Account userAccountData;
    bool userAccountDataMemoized;
    uint assetPrice;
    bool assetPriceMemoized;
    bytes data;
  }

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode) AaveV3Borrower(addressesProvider, interestRateMode) {}

  ///@notice fetches and optionally memoizes the owner of `this` contract in additional data
  ///@param m the memoizer
  ///@return owner the owner of the funds
  function getOwnerAddress(Memoizer memory m) internal view virtual returns (address);

  ///@notice fetches and memoizes the reserve data of a particular asset on AAVE
  ///@param token the asset whose reserve data is needed
  ///@param m the memoizer
  ///@return reserveData of `token`
  function reserveData(IERC20 token, Memoizer memory m) internal view returns (DataTypes.ReserveData memory) {
    if (!m.reserveDataMemoized) {
      m.reserveDataMemoized = true;
      m.reserveData = POOL.getReserveData(address(token));
    }
    return m.reserveData;
  }

  ///@notice fetches and memoizes the overlying IERC20 of a given asset
  ///@param token the asset whose overlying is needed
  ///@param m the memoizer
  ///@return overlying of the asset
  function overlying(IERC20 token, Memoizer memory m) internal view returns (IERC20) {
    return IERC20(reserveData(token, m).aTokenAddress);
  }

  ///@notice fetches and memoizes the overlying asset balance of `this` contract
  ///@param token the underlying asset
  ///@param m the memoizer
  ///@return balance of the overlying of the asset
  function overlyingBalanceOf(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.overlyingBalanceOfMemoized) {
      m.overlyingBalanceOfMemoized = true;
      IERC20 aToken = overlying(token, m);
      // aToken will be 0x if token is not a valid asset for AAVE.
      if (aToken != IERC20(address(0))) {
        m.overlyingBalanceOf = aToken.balanceOf(getOwnerAddress(m));
      }
    }
    return m.overlyingBalanceOf;
  }

  ///@notice fetches and memoizes the token balance of `this` contract
  ///@param token the asset whose balance is needed.
  ///@param m the memoizer
  ///@return balance of the asset
  function balanceOf(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.balanceOfMemoized) {
      m.balanceOfMemoized = true;
      m.balanceOf = token.balanceOf(getOwnerAddress(m));
    }
    return m.balanceOf;
  }

  /**
   * @notice retrieves the address of the non transferrable debt token overlying of some asset
   * @param token the underlying asset
   * @param m the memoizer
   * @return debtTkn the overlying debt token
   * @dev no need to memoize this since the information is already memoized in `m.reserveData`
   */
  function debtToken(IERC20 token, Memoizer memory m) internal view returns (ICreditDelegationToken debtTkn) {
    debtTkn = INTEREST_RATE_MODE == 1
      ? ICreditDelegationToken(reserveData(token, m).stableDebtTokenAddress)
      : ICreditDelegationToken(reserveData(token, m).variableDebtTokenAddress);
  }

  ///@notice fetches and memoizes the debt of `this` contract in a particular asset
  ///@param token the asset whose debt balance is being queried
  ///@param m the memoizer
  ///@return debt in asset
  ///@dev user can only borrow underlying in variable or stable, not both
  function debtBalanceOf(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.debtBalanceOfMemoized) {
      m.debtBalanceOfMemoized = true;
      ICreditDelegationToken dtkn = debtToken(token, m);
      // if token is not an approved asset of the AAVE, the pool's mapping will return 0x for the debt token.
      if (address(dtkn) != address(0)) {
        m.debtBalanceOf = dtkn.balanceOf(getOwnerAddress(m));
      }
    }
    return m.debtBalanceOf;
  }

  ///@notice fetches and memoizes `this` contract's account data on the pool
  ///@param m the memoizer
  ///@return accountData of `this` contract
  function userAccountData(Memoizer memory m) internal view returns (Account memory) {
    if (!m.userAccountDataMemoized) {
      m.userAccountDataMemoized = true;
      (
        m.userAccountData.collateral,
        m.userAccountData.debt,
        m.userAccountData.borrowPower, // avgLtv * sumCollateralEth - sumDebtEth
        m.userAccountData.liquidationThreshold,
        m.userAccountData.ltv,
        m.userAccountData.health // avgLiquidityThreshold * sumCollateralEth / sumDebtEth  -- should be less than 10**18
      ) = POOL.getUserAccountData(getOwnerAddress(m));
    }
    return m.userAccountData;
  }

  ///@notice fetches and memoizes the current block's price of an asset
  ///@param token the asset whose price is needed
  ///@param m the memoizer
  ///@return price of one unit of asset expressed in USD with 8 decimals precision
  function assetPrice(IERC20 token, Memoizer memory m) internal view returns (uint) {
    if (!m.assetPriceMemoized) {
      m.assetPriceMemoized = true;
      m.assetPrice = ORACLE.getAssetPrice(address(token));
    }
    return m.assetPrice;
  }

  ///@notice returns line of credit of `this` contract in the form of a pair (maxRedeem, maxBorrow) corresponding respectively
  ///to the max amount of `token` this contract can withdraw from the pool, and the max amount of `token` it can borrow in addition (after withdrawing `maxRedeem`)
  ///@param token the asset one wishes to get from the pool
  ///@param m the memoizer
  ///@param target if `maxRedeem < target` will try also borrowing. Otherwise `maxBorrow = 0`
  ///@return maxRedeemableUnderlying the max amount of `token` this contract can withdraw from the pool
  ///@return maxBorrowAfterRedeemInUnderlying the max amount of `token` this contract can borrow from the pool after withdrawing `maxRedeemableUnderlying`
  function maxGettableUnderlying(IERC20 token, Memoizer memory m, uint target)
    internal
    view
    returns (uint maxRedeemableUnderlying, uint maxBorrowAfterRedeemInUnderlying)
  {
    Underlying memory underlying; // asset parameters
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      /*liquidationBonus*/
      ,
      underlying.decimals,
      /*reserveFactor*/
      ,
      /*emode_category*/
    ) = ReserveConfiguration.getParams(reserveData(token, m).configuration);

    // redeemPower = account.liquidationThreshold * account.collateral - account.debt
    Account memory _userAccountData = userAccountData(m);
    uint redeemPower =
      (_userAccountData.liquidationThreshold * _userAccountData.collateral - _userAccountData.debt * 10 ** 4) / 10 ** 4;

    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())
    maxRedeemableUnderlying = (
      redeemPower // in 10**underlying.decimals
        * 10 ** underlying.decimals * 10 ** 4
    ) / (underlying.liquidationThreshold * assetPrice(token, m));

    maxRedeemableUnderlying =
      (maxRedeemableUnderlying < overlyingBalanceOf(token, m)) ? maxRedeemableUnderlying : overlyingBalanceOf(token, m);

    if (target <= maxRedeemableUnderlying) {
      return (maxRedeemableUnderlying, 0);
    }
    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = (maxRedeemableUnderlying * underlying.ltv) / 10 ** 4;

    uint borrowPowerInUnderlying = (_userAccountData.borrowPower * 10 ** underlying.decimals) / assetPrice(token, m);

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    // max borrow power in underlying after max redeem has been withdrawn
    maxBorrowAfterRedeemInUnderlying = borrowPowerInUnderlying - borrowPowerImpactOfRedeemInUnderlying;
  }
}
