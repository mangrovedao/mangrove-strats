// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {SmartRouter, AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
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
  /// TODO check strict boolean and transfer more than amount only if true
  function __pull__(RL.RoutingOrder memory routingOrder, bool strict) internal virtual override returns (uint) {
    Memoizer memory m;

    // gets account info
    (uint maxWithdraw,) = maxGettableUnderlying(routingOrder.token, m, routingOrder.reserveId, routingOrder.amount);
    Account memory account = userAccountData(m, routingOrder.reserveId);
    uint toWithdraw;

    if (account.debt > 0) {
      // if there is no debt, we can withdraw the full amount
      uint creditLine = creditLineOf(routingOrder.token);
      uint maxCreditLine = maxWithdraw * creditLine / MAX_CREDIT_LINE;
      toWithdraw = routingOrder.amount > maxCreditLine ? maxCreditLine : routingOrder.amount;
    } else {
      // else redeem the max amount
      uint balance = overlyingBalanceOf(routingOrder.token, m, routingOrder.reserveId);
      toWithdraw = routingOrder.amount > balance ? balance : routingOrder.amount;
    }
    // transfer the IOU tokens from reserveId
    require(
      TransferLib.transferTokenFrom(overlying(routingOrder.token, m), routingOrder.reserveId, address(this), toWithdraw),
      "AaveLogic/OverlyingTransferFail"
    );

    // since this contract will be delegate called, msg.sender is maker contract
    uint redeemed = _redeem(routingOrder.token, toWithdraw, msg.sender);
    return redeemed;
  }

  /// @inheritdoc AbstractRouter
  /// @dev tries to repay existing debt first and then supplies the rest
  function __push__(RL.RoutingOrder memory routingOrder) internal virtual override returns (uint) {
    Memoizer memory m;
    // just in time approval of the POOL in order to be able to deposit funds
    _approveLender(routingOrder.token, routingOrder.amount);
    uint leftToPush = routingOrder.amount;
    // tries to repay existing debt
    if (debtBalanceOf(routingOrder.token, m, routingOrder.reserveId) > 0) {
      uint repaid = _repay(routingOrder.token, leftToPush, routingOrder.reserveId);
      leftToPush -= repaid;
    }
    // supplies the rest
    if (leftToPush > 0) {
      bytes32 reason = _supply(routingOrder.token, leftToPush, routingOrder.reserveId, true);
      require(reason == bytes32(0), "AaveLogic/SupplyFailed");
    }
    return routingOrder.amount;
  }

  ///@inheritdoc AbstractRouter
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  function __checkList__(RL.RoutingOrder calldata routingOrder) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    IERC20 aToken = overlying(routingOrder.token);
    require(address(aToken) != address(0), "AaveLogic/TokenNotSupportedByPool");
    // needs to pull aTokens from reserve Id
    uint allowance = aToken.allowance(routingOrder.reserveId, address(this));
    require(allowance >= type(uint96).max || allowance >= routingOrder.amount, "AaveLogic/CannotPullOverlying");
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(RL.RoutingOrder calldata routingOrder) public view virtual override returns (uint balance) {
    Memoizer memory m;
    balance = overlyingBalanceOf(routingOrder.token, m, routingOrder.reserveId);
    balance += balanceOf(routingOrder.token, m, routingOrder.reserveId);
  }
}
