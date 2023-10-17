// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {AaveMemoizer} from "@mgv-strats/src/strategies/integrations/AaveMemoizer.sol";

contract AaveLogic is AbstractRoutingLogic, AaveMemoizer {
  /// @notice The maximum credit line to be redeemed
  /// * Credit line is the maximum amount that can be borrowed to stay above the liquidation threshold (health factor > 1)
  /// * If the protocol can redeem a maximum of 100 tokens and the credit line is 50, then the protocol can redeem 50 tokens
  /// to keep a 50 tokens buffer above the liquidation threshold
  /// * 100 means we can redeem or borrow 100% of the credit line
  /// * 0 means we can't redeem or borrow anything
  /// * If the user has no debt, this number will be ignored
  uint8 internal immutable MAX_CREDIT_LINE = 100;

  /// @notice The Credit line decrease for a given owner
  mapping(address owner => mapping(IERC20 token => uint8)) private credit_line_decrease;

  constructor(uint pullGasReq_, uint pushGasReq_, address addressesProvider, uint referralCode, uint interestRateMode)
    AbstractRoutingLogic(pullGasReq_, pushGasReq_)
    AaveMemoizer(addressesProvider, referralCode, interestRateMode)
  {}

  /// @notice Gets the maximum amount of underlying that can be redeemed
  /// @param owner The owner of the tokens
  /// @param token The token to redeem
  /// @return credit_line The maximum amount of underlying that can be redeemed in percentage
  function creditLineOf(address owner, IERC20 token) public view returns (uint8 credit_line) {
    credit_line = MAX_CREDIT_LINE;
    uint8 decrease = credit_line_decrease[owner][token];
    if (decrease > 0) {
      credit_line -= decrease;
    }
  }

  /// @notice Sets the maximum credit line for a given token and user
  /// @param creditLine The maximum credit line to be redeemed
  /// @param token The token to set the credit line for
  function setMaxCreditLine(uint8 creditLine, IERC20 token) public {
    require(creditLine <= MAX_CREDIT_LINE, "AaveLogic/InvalidCreditLine");
    credit_line_decrease[msg.sender][token] = MAX_CREDIT_LINE - creditLine;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @dev will only transfer up to the maximum defined credit line
  /// * if no debt, will transfer the full amount anyway
  function executePullLogic(IERC20 token, uint amount, DispatcherRouter.PullStruct calldata pullData)
    external
    virtual
    override
    returns (uint)
  {
    Memoizer memory m;

    // gets account info
    (uint maxWithdraw,) = maxGettableUnderlying(token, m, pullData.owner, amount);
    Account memory account = userAccountData(m, pullData.owner);
    uint toWithdraw;

    if (account.debt > 0) {
      // if there is no debt, we can withdraw the full amount
      uint creditLine = creditLineOf(pullData.owner, token);
      uint maxCreditLine = maxWithdraw * creditLine / MAX_CREDIT_LINE;
      toWithdraw = amount > maxCreditLine ? maxCreditLine : amount;
    } else {
      // else redeem the max amount
      uint balance = overlying(token, m).balanceOf(pullData.owner);
      toWithdraw = amount > balance ? balance : amount;
    }

    // gets the overlying tokens
    DispatcherRouter router = DispatcherRouter(msg.sender);
    require(router.executeTransfer(token, overlying(token, m), toWithdraw, pullData), "AaveLogic/TransferFailed");
    // redeem on aave
    uint redeemed = _redeem(token, toWithdraw, pullData.caller);

    return redeemed;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @dev tries to repay existing debt first and then supplies the rest
  function executePushLogic(IERC20 token, uint amount, DispatcherRouter.PushStruct calldata pushData)
    external
    virtual
    override
    returns (uint)
  {
    Memoizer memory m;
    uint leftToPush = amount;

    // tries to repay existing debt
    if (debtBalanceOf(token, m, pushData.owner) > 0) {
      uint repaid = _repay(token, leftToPush, pushData.owner);
      leftToPush -= repaid;
    }

    // supplies the rest
    if (leftToPush > 0) {
      bytes32 reason = _supply(token, leftToPush, pushData.owner, true);
      require(reason == bytes32(0), "AaveLogic/SupplyFailed");
    }

    return amount;
  }
}
