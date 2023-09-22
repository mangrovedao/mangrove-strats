// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MonoRouter, AbstractRouter} from "../../abstract/MonoRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration, DataTypes} from "../AaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/// @title `AaveDispatchedRouter` is a router contract for Aave used by the `Dispatcher` contract.
/// @dev No tokens should be directly sent to this contract
/// @dev This contract is to be used by the `Dispatcher` contract.
contract AaveDispatchedRouter is MonoRouter, AaveMemoizer {
  /// @notice Holds the storage key for this contract specific storage
  bytes32 internal immutable STORAGE_KEY;

  /// @notice The maximum credit line to be redeemed
  /// * 100 means we can redeem or borrow 100% of the credit line
  /// * 0 means we can't redeem or borrow anything
  uint internal immutable MAX_CREDIT_LINE = 100;

  /// @notice Data for a reserve <=> token pair
  /// @param deposit_on_push Whether to deposit on push
  /// @param credit_line_decrease The Credit line decrease for a given token and reserveId
  struct TokenReserveData {
    bool deposit_on_push;
    uint8 credit_line_decrease;
  }

  /// @notice Storage Layout for `AaveDispatchedRouter`
  /// @param token_reserve_data The data for a reserve <=> token pair
  struct AaveDispatcherStorage {
    mapping(address => mapping(IERC20 => TokenReserveData)) token_reserve_data;
  }

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
  /// @param data The data to set
  function setTokenReserveData(address reserveId, IERC20 token, bytes calldata data) external onlyBound {
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    TokenReserveData memory tokenReserveData = abi.decode(data, (TokenReserveData));
    s.token_reserve_data[reserveId][token] = tokenReserveData;
  }

  /// @notice Gets the max credit line for a given token and reserveId
  /// @dev This has to be called in order to get the maximum credit line that can be used by this contract
  /// @param token The token to get the buffer size for
  /// @param reserveId The reserveId to get the buffer size for
  /// @return credit_line max credit line that can be used by this contract
  function getBufferSize(IERC20 token, address reserveId) internal view returns (uint credit_line) {
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    credit_line = MAX_CREDIT_LINE;
    uint decrease = s.token_reserve_data[reserveId][token].credit_line_decrease;
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
  function __checkList__(IERC20 token, address reserveId) internal view override {
    require(token.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
    Memoizer memory m;
    IERC20 overlying = overlying(token, m);
    require(overlying.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
  }

  /// @notice pulls amount of underlying that can be redeemed
  /// @inheritdoc	AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool) internal virtual override returns (uint) {
    Memoizer memory m;
    setOwnerAddress(m, reserveId);

    uint localBalance = balanceOf(token, m);
    uint missing = amount > localBalance ? amount - localBalance : 0;
    if (missing > 0) {
      (uint maxWithdraw,) = maxGettableUnderlying(token, m, missing);
      uint creditLine = getBufferSize(token, reserveId);
      uint maxCreditLine = maxWithdraw * creditLine / MAX_CREDIT_LINE;
      uint toWithdraw = amount > maxCreditLine ? maxCreditLine : amount;
      require(
        TransferLib.transferTokenFrom(overlying(token, m), reserveId, address(this), toWithdraw),
        "AaveDispatchedRouter/pullFailed"
      );
      _redeem(token, toWithdraw, address(this), false);
      require(
        TransferLib.transferTokenFrom(token, address(this), msg.sender, amount), "AaveDispatchedRouter/pullFailed"
      );
    }
    return amount;
  }

  /// @notice Deposit underlying tokens to the reserve
  /// @dev Can supply the underlying on behalf (if opted in by the reserve)
  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint) {
    bool deposit = getAaveDispatcherStorage().token_reserve_data[reserveId][token].deposit_on_push;
    if (deposit) {
      _supply(token, amount, reserveId, false);
    } else {
      require(TransferLib.transferTokenFrom(token, msg.sender, reserveId, amount), "AaveDispatchedRouter/pushFailed");
    }
    return amount;
  }

  ///@notice returns the amount of asset that the reserve has, either locally or on pool
  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {
    Memoizer memory m;
    setOwnerAddress(m, reserveId);
    return overlyingBalanceOf(token, m) + balanceOf(token, m);
  }
}
