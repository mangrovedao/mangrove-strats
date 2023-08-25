// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20, AaveV3Lender} from "./AaveV3Lender.sol";
import {IPriceOracleGetter} from "mgv_strat_src/strategies/vendor/aave/v3/IPriceOracleGetter.sol";
import {IPoolAddressesProvider} from "mgv_strat_src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";

/// @title This contract provides a collection of interactions capabilities with AAVE-v3 to whichever contract inherits it
/// `AaveV3Borrower` contracts are in particular able to perform basic pool interactions (lending, borrowing, supplying and repaying)
contract AaveV3Borrower is AaveV3Lender {
  /// @notice address of AAVE price oracle (must be the price oracle used by the pool)
  /// @dev price oracle and pool address can be obtained from AAVE's address provider contract
  IPriceOracleGetter public immutable ORACLE;

  /// @notice interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  uint public immutable INTEREST_RATE_MODE;

  /// @notice the e code used to register the integrator originating the operation, for potential rewards. 0 since the action is executed directly by the user, without any middle-man.
  uint16 public constant REFERRAL_CODE = uint16(0);

  /// @notice contract's constructor
  /// @param addressesProvider address of AAVE's address provider
  /// @param interestRateMode interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode) AaveV3Lender(addressesProvider) {
    INTEREST_RATE_MODE = interestRateMode;

    address _priceOracle = IPoolAddressesProvider(addressesProvider).getAddress("PRICE_ORACLE");
    require(_priceOracle != address(0), "AaveModule/0xPriceOracle");
    ORACLE = IPriceOracleGetter(_priceOracle);
  }

  /// @notice tries to borrow some assets from the pool
  /// @param token the asset one is borrowing
  /// @param amount the amount of assets one is borrowing
  /// @param onBehalf the account whose collateral is being used to borrow (caller must be approved by `onBehalf` -if different- using `approveDelegation` from the corresponding debt token (variable or stable))
  /// @param noRevert does not revert if borrow throws, but returns the reason
  /// @return reason the reason for the failure if any
  function _borrow(IERC20 token, uint amount, address onBehalf, bool noRevert) internal returns (bytes32 reason) {
    try POOL.borrow(address(token), amount, INTEREST_RATE_MODE, REFERRAL_CODE, onBehalf) {
      return bytes32(0);
    } catch Error(string memory reason_) {
      require(noRevert, reason_);
      return bytes32(bytes(reason_));
    }
  }

  /// @notice repays debt to the pool
  /// @param token the asset one is repaying
  /// @param amount of assets one is repaying
  /// @param onBehalf account whose debt is being repaid
  /// @param noRevert does not revert if repay throws, but returns the reason
  /// @return repaid the repaid amount
  /// @return reason the reason for the failure if any
  function _repay(IERC20 token, uint amount, address onBehalf, bool noRevert)
    internal
    returns (uint repaid, bytes32 reason)
  {
    try POOL.repay(address(token), amount, INTEREST_RATE_MODE, onBehalf) returns (uint repaid_) {
      return (repaid_, bytes32(0));
    } catch Error(string memory reason_) {
      require(noRevert, reason_);
      return (0, bytes32(bytes(reason_)));
    }
  }
}
