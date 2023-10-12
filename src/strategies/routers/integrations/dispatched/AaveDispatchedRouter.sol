// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MonoRouter, AbstractRouter, ApprovalInfo} from "../../abstract/MonoRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration, DataTypes} from "../AaveMemoizer.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title `AaveDispatchedRouter` is a router contract for Aave used by the `Dispatcher` contract.
/// @dev No tokens should be directly sent to this contract
/// @dev This contract is to be used by the `Dispatcher` contract.
contract AaveDispatchedRouter is MonoRouter, AaveMemoizer {
  /// @notice Holds the storage key for this contract specific storage
  bytes32 internal immutable STORAGE_KEY;

  /// @notice The maximum credit line to be redeemed
  /// * Credit line is the maximum amount that can be borrowed to stay above the liquidation threshold (health factor > 1)
  /// * If the protocol can redeem a maximum of 100 tokens and the credit line is 50, then the protocol can redeem 50 tokens
  /// to keep a 50 tokens buffer above the liquidation threshold
  /// * 100 means we can redeem or borrow 100% of the credit line
  /// * 0 means we can't redeem or borrow anything
  /// * If the user has no debt, this number will be ignored
  uint8 internal immutable MAX_CREDIT_LINE = 100;

  /// @notice Data for a reserve <=> token pair
  /// @param credit_line_decrease The Credit line decrease for a given token and reserveId
  struct TokenReserveData {
    uint8 credit_line_decrease;
  }

  /// @notice Storage Layout for `AaveDispatchedRouter`
  /// @param token_reserve_data The data for a reserve <=> token pair
  struct AaveDispatcherStorage {
    mapping(address => mapping(IERC20 => TokenReserveData)) token_reserve_data;
  }

  /// @notice contract's constructor
  /// @param routerGasreq_ The gas requirement for the router
  /// @param addressesProvider The address of the Aave addresses provider
  /// @param interestRateMode The interest rate mode to use
  /// @param storage_key The storage key for this contract specific storage
  constructor(uint routerGasreq_, address addressesProvider, uint interestRateMode, string memory storage_key)
    MonoRouter(routerGasreq_)
    AaveMemoizer(addressesProvider, interestRateMode)
  {
    STORAGE_KEY = keccak256(abi.encodePacked(storage_key));
  }

  /// @notice Get the storage struct for this contract
  /// @return s The storage struct
  function getAaveDispatcherStorage() internal view returns (AaveDispatcherStorage storage s) {
    bytes32 key = STORAGE_KEY;
    assembly {
      s.slot := key
    }
  }

  /// @notice Sets the data for a reserve <=> token pair
  /// @dev This can only be called by the reserveId
  /// @param reserveId The reserveId to set the data for
  /// @param token The token to set the data for
  /// @param data must be encoded uint8 as bytes (credit_line in percentage range 0-100)
  function setAaveCreditLine(address reserveId, IERC20 token, bytes calldata data) external onlyBound {
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    uint8 credit_line = abi.decode(data, (uint8));
    require(credit_line <= MAX_CREDIT_LINE, "AaveDispatchedRouter/InvalidCreditLineDecrease");
    s.token_reserve_data[reserveId][token].credit_line_decrease = MAX_CREDIT_LINE - credit_line;
  }

  /// @notice Gets the data for a reserve <=> token pair
  /// @dev This can only be called by the reserveId
  /// @param reserveId The reserveId to get the data for
  /// @param token The token to get the data for
  /// @return credit_line The credit line for a given token and reserveId
  function getAaveCreditLine(address reserveId, IERC20 token, bytes calldata) external view returns (uint8) {
    return creditLineOf(token, reserveId);
  }

  /// @notice Gets the max credit line for a given token and reserveId
  /// @dev This has to be called in order to get the maximum credit line that can be used by this contract
  /// @param token The token to get the buffer size for
  /// @param reserveId The reserveId to get the buffer size for
  /// @return credit_line max credit line that can be used by this contract
  function creditLineOf(IERC20 token, address reserveId) internal view returns (uint8 credit_line) {
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    credit_line = MAX_CREDIT_LINE;
    uint8 decrease = s.token_reserve_data[reserveId][token].credit_line_decrease;
    if (decrease > 0) {
      credit_line -= decrease;
    }
  }

  ///@inheritdoc AbstractRouter
  function __activate__(IERC20 token) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  /// @dev Checks if user gave allowance for token and overlying
  /// @inheritdoc	AbstractRouter
  function __checkList__(IERC20 token, address reserveId, address) internal view override {
    require(token.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
    Memoizer memory m;
    IERC20 overlying = overlying(token, m);
    require(overlying.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/OverlyingNotApproved");
  }

  /// @notice pulls amount of underlying that can be redeemed
  /// @dev if the user has no debt, the max credit line will be ignored
  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool, ApprovalInfo calldata)
    internal
    virtual
    override
    returns (uint)
  {
    Memoizer memory m;

    uint localBalance = balanceOf(token, m, reserveId);
    uint fromLocal = amount > localBalance ? localBalance : amount;
    uint missing = amount - fromLocal;

    uint pulled;

    if (fromLocal > 0) {
      require(TransferLib.transferTokenFrom(token, reserveId, msg.sender, fromLocal), "AaveDispatchedRouter/pullFailed");
      pulled += fromLocal;
    }
    if (missing > 0) {
      (uint maxWithdraw,) = maxGettableUnderlying(token, m, reserveId, missing);
      Account memory account = userAccountData(m, reserveId);
      uint toWithdraw;
      if (account.debt > 0) {
        uint creditLine = creditLineOf(token, reserveId);
        uint maxCreditLine = maxWithdraw * creditLine / MAX_CREDIT_LINE;
        toWithdraw = missing > maxCreditLine ? maxCreditLine : missing;
      } else {
        uint balance = overlying(token, m).balanceOf(reserveId);
        toWithdraw = missing > balance ? balance : missing;
      }
      require(
        TransferLib.transferTokenFrom(overlying(token, m), reserveId, address(this), toWithdraw),
        "AaveDispatchedRouter/pullFailed"
      );
      (uint redeemed,) = _redeem(token, toWithdraw, address(this), false);
      require(
        TransferLib.transferTokenFrom(token, address(this), msg.sender, redeemed), "AaveDispatchedRouter/pullFailed"
      );
      pulled += redeemed;
    }
    return pulled;
  }

  /// @notice Deposit underlying tokens to the reserve
  /// @dev First repay debt if any and then supply the underlying on behalf
  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "AavePrivateRouter/pushFailed");
    uint _leftToPush = amount;
    Memoizer memory m;
    // repay debt if any
    if (debtBalanceOf(token, m, reserveId) > 0) {
      (uint repaid, bytes32 reason) = _repay(token, amount, reserveId, true);
      require(reason == bytes32(0), "AaveDispatchedRouter/pushFailed");
      _leftToPush -= repaid;
    }
    // supply
    if (_leftToPush > 0) {
      bytes32 reason = _supply(token, _leftToPush, reserveId, true);
      require(reason == bytes32(0), "AaveDispatchedRouter/pushFailed");
    }
    return amount;
  }

  ///@notice returns the amount of asset that the reserve has, either locally or on pool
  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    Memoizer memory m;
    return overlyingBalanceOf(token, m, reserveId) + balanceOf(token, m, reserveId);
  }
}
