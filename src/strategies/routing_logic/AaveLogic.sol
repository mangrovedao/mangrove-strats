// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {SmartRouter, AbstractRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AaveMemoizer} from "@mgv-strats/src/strategies/integrations/AaveMemoizer.sol";
import {AaveLogicStorage} from "./AaveLogicStorage.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title AaveLogic
/// @notice Routing logic for Aave
contract AaveLogic is AbstractRouter, AaveMemoizer {
  /// @notice The maximum credit line to be redeemed
  /// * Credit line is the maximum amount that can be borrowed to stay above the liquidation threshold (health factor > 1)
  /// * If the protocol can redeem a maximum of 100 tokens and the credit line is 50, then the protocol can redeem 50 tokens
  /// to keep a 50 tokens buffer above the liquidation threshold
  /// * 100 means we can redeem or borrow 100% of the credit line
  /// * 0 means we can't redeem or borrow anything
  /// * If the user has no debt, this number will be ignored
  uint8 internal immutable MAX_CREDIT_LINE = 100;

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode) AaveMemoizer(addressesProvider, interestRateMode) {}

  /// @notice Gets the maximum amount of underlying that can be redeemed
  /// @param token The token to redeem
  /// @return credit_line The maximum amount of underlying that can be redeemed in percentage
  function creditLineOf(IERC20 token) public view returns (uint8 credit_line) {
    credit_line = MAX_CREDIT_LINE;
    uint8 decrease = AaveLogicStorage.getStorage().credit_line_decrease[token];
    if (decrease > 0) {
      credit_line -= decrease;
    }
  }

  /// @notice Sets the maximum credit line for a given token and user
  /// @param creditLine The maximum credit line to be redeemed
  /// @param token The token to set the credit line for
  function setMaxCreditLine(uint8 creditLine, IERC20 token) public onlyAdmin {
    require(creditLine <= MAX_CREDIT_LINE, "AaveLogic/InvalidCreditLine");
    AaveLogicStorage.getStorage().credit_line_decrease[token] = MAX_CREDIT_LINE - creditLine;
  }

  /// @inheritdoc AbstractRouter
  /// @dev will only transfer up to the maximum defined credit line
  /// * if no debt, will transfer the full amount anyway
  function __pull__(IERC20 token, uint amount, bytes memory) internal virtual override returns (uint) {
    Memoizer memory m;

    // gets account info
    (uint maxWithdraw,) = maxGettableUnderlying(token, m, admin(), amount);
    Account memory account = userAccountData(m, admin());
    uint toWithdraw;

    if (account.debt > 0) {
      // if there is no debt, we can withdraw the full amount
      uint creditLine = creditLineOf(token);
      uint maxCreditLine = maxWithdraw * creditLine / MAX_CREDIT_LINE;
      toWithdraw = amount > maxCreditLine ? maxCreditLine : amount;
    } else {
      // else redeem the max amount
      uint balance = overlyingBalanceOf(token, m, admin());
      toWithdraw = amount > balance ? balance : amount;
    }
    // transfer the IOU tokens from admin's wallet
    require(
      TransferLib.transferTokenFrom(overlying(token, m), admin(), address(this), toWithdraw),
      "AaveLogic/OverlyingTransferFail"
    );

    // since this contract will be delegate called, msg.sender is maker contract
    uint redeemed = _redeem(token, toWithdraw, msg.sender);
    return redeemed;
  }

  /// @inheritdoc AbstractRouter
  /// @dev tries to repay existing debt first and then supplies the rest
  function __push__(IERC20 token, uint amount, bytes memory) internal virtual override returns (uint) {
    Memoizer memory m;
    uint leftToPush = amount;

    // tries to repay existing debt
    if (debtBalanceOf(token, m, admin()) > 0) {
      uint repaid = _repay(token, leftToPush, admin());
      leftToPush -= repaid;
    }
    // supplies the rest
    if (leftToPush > 0) {
      bytes32 reason = _supply(token, leftToPush, admin(), true);
      require(reason == bytes32(0), "AaveLogic/SupplyFailed");
    }
    return amount;
  }

  ///@inheritdoc AbstractRouter
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  function __checkList__(IERC20 token, bytes calldata) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    IERC20 aToken = overlying(token);
    require(address(aToken) != address(0), "AaveLogic/TokenNotSupportedByPool");
    // needs to pull aTokens from admin's account
    require(aToken.allowance(admin(), address(this)) > 0, "AaveLogic/CannotPullOverlying");
    // POOL needs to pull underlying from this when supplying to the pool
    require(token.allowance(address(this), address(POOL)) > 0, "AaveLogic/PoolCannotPullUnderlying");
  }

  ///@inheritdoc AbstractRouter
  function __activate__(IERC20 token, bytes calldata) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, bytes calldata) public view virtual override returns (uint balance) {
    Memoizer memory m;
    balance = overlyingBalanceOf(token, m, admin());
    balance += balanceOf(token, m, admin());
  }
}
