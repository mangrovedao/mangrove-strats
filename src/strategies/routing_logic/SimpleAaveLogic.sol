// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "./abstract/AbstractRoutingLogic.sol";
import {AaveMemoizer, IPoolAddressesProvider} from "@mgv-strats/src/strategies/integrations/AaveMemoizer.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title SimpleAaveLogic
/// @notice Routing logic for Aave without credit line
contract SimpleAaveLogic is AaveMemoizer, AbstractRoutingLogic {
  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(IPoolAddressesProvider addressesProvider, uint interestRateMode)
    AaveMemoizer(addressesProvider, interestRateMode)
  {}

  ///@inheritdoc AbstractRoutingLogic
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict) external override returns (uint pulled) {
    Memoizer memory m;

    uint amount_ = strict ? amount : overlyingBalanceOf(token, m, fundOwner);
    if (amount_ == 0) {
      return 0;
    }
    // fetching overlyings from owner's account
    // will fail if `address(this)` is not approved for it.
    require(
      TransferLib.transferTokenFrom(overlying(token, m), fundOwner, address(this), amount_),
      "SimpleAaveLogic/TransferFailed"
    );
    // redeem from the pool and send underlying to calling maker contract
    (, pulled) = _redeem(token, amount_, msg.sender, false);
  }

  ///@inheritdoc AbstractRoutingLogic
  function pushLogic(IERC20 token, address fundOwner, uint amount) external override returns (uint pushed) {
    // funds are on MakerContract, they need first to be transferred to this contract before being deposited
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "SimpleAaveLogic/TransferFailed");

    // just in time approval of the POOL in order to be able to deposit funds
    _approveLender(token, amount);
    bytes32 reason = _supply(token, amount, fundOwner, true);
    require(reason == bytes32(0), string(abi.encodePacked(reason)));
    return amount;
  }

  ///@inheritdoc AbstractRoutingLogic
  function balanceLogic(IERC20 token, address fundOwner) external view override returns (uint balance) {
    Memoizer memory m;
    balance = overlyingBalanceOf(token, m, fundOwner);
  }
}
