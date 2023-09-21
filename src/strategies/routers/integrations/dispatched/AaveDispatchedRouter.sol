// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MonoRouter, AbstractRouter} from "../../abstract/MonoRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer} from "../AaveMemoizer.sol";
import {ReserveConfiguration, DataTypes} from "../../abstract/AbstractAaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/// @title `AaveDispatchedRouter` is a router contract for Aave used by the `Dispatcher` contract.
/// @dev No tokens should be directly sent to this contract
/// @dev This contract is to be used by the `Dispatcher` contract.
contract AaveDispatchedRouter is MonoRouter, AaveMemoizer {
  /// @notice Holds the storage key for this contract specific storage
  bytes32 internal immutable STORAGE_KEY;

  /// @notice The default buffer size for Aave credit line
  /// * 100 means we can redeem or borrow 100% of the credit line
  /// * 0 means we can't redeem or borrow anything
  uint internal immutable DEFAULT_BUFFER_SIZE = 100;

  /// @notice Storage Layout for `AaveDispatchedRouter`
  struct AaveDispatcherStorage {
    /// @notice The buffer size decrease for a given token and reserveId
    mapping(address => mapping(IERC20 => uint)) buffer_size_decrease;
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

  /// @notice Sets the buffer size decrease for a given token and reserveId
  /// @dev This is used to decrease the buffer size for a given token and reserveId
  /// * This can only be called by the reserveId
  /// @param token The token to set the buffer size decrease for
  /// @param reserveId The reserveId to set the buffer size decrease for
  /// @param amount The amount to decrease the buffer size by
  function setBufferSizeDecrease(IERC20 token, address reserveId, uint amount) external onlyCaller(reserveId) {
    require(amount <= 100, "AaveDispatchedRouter/InvalidAmount");
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    s.buffer_size_decrease[reserveId][token] = amount;
  }

  /// @notice Gets the buffer size for a given token and reserveId
  /// @dev This has to be called in order to get the maximum credit line that can be used by this contract
  /// @param token The token to get the buffer size for
  /// @param reserveId The reserveId to get the buffer size for
  /// @return buffer_size The buffer size (or max credit line usage)
  function getBufferSize(IERC20 token, address reserveId) internal view returns (uint buffer_size) {
    AaveDispatcherStorage storage s = getAaveDispatcherStorage();
    buffer_size = DEFAULT_BUFFER_SIZE;
    uint decrease = s.buffer_size_decrease[reserveId][token];
    if (decrease > 0) {
      buffer_size -= decrease;
    }
  }

  /// @dev Checks if user gave allowance for token and overlying
  /// @inheritdoc	AbstractRouter
  function __checkList__(IERC20 token, address reserveId) internal view override {
    require(token.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
    Memoizer memory m;
    IERC20 overlying = overlying(token, m);
    require(overlying.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
  }

  function __pull__(IERC20 token, address reserveId, uint amount, bool strict) internal virtual override returns (uint) {
    Memoizer memory m;
    setOwnerAddress(m, reserveId);

    uint localBalance = balanceOf(token, m);
    uint missing = amount > localBalance ? amount - localBalance : 0;
    if (missing > 0) {
      (uint maxWithdraw, uint maxBorrow) = maxGettableUnderlying(token, m, missing);

      if (maxWithdraw > 0) {}
    }
  }

  /// @notice Deposit undeerlying tokens to the reserve
  /// @dev No Aave supply with the underlying
  /// @inheritdoc	AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, reserveId, amount), "AaveDispatchedRouter/pushFailed");
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
