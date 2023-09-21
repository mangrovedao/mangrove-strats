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
  bytes32 internal immutable STORAGE_KEY;

  uint internal immutable DEFAULT_BUFFER_SIZE = 100;

  struct AaveDispatcherStorage {
    mapping(address => mapping(IERC20 => uint)) buffer_size;
  }

  constructor(uint routerGasreq_, address addressesProvider, uint interestRateMode, string memory storage_key)
    MonoRouter(routerGasreq_)
    AaveMemoizer(addressesProvider, interestRateMode)
  {
    STORAGE_KEY = keccak256(abi.encodePacked(storage_key));
  }

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

  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {}
}
