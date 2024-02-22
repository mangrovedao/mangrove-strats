// SPDX-License-Identifier:	MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "./abstract/AbstractRoutingLogic.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title SimpleRoutingLogic
/// @author Mangrove DAO
/// @notice SimpleRoutingLogic is a simple routing logic that pulls (pushes) liquidity directly from (to) the an offer owner's account
/// @dev on Mangore Order, default logic is SimpleRoutingLogic, So using this contract as a standalone logic is possible
/// * but it is preferrable to set the logic for pulling/pushing as address(0)
contract SimpleRoutingLogic is AbstractRoutingLogic {
  /// @inheritdoc AbstractRoutingLogic
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict)
    public
    virtual
    override
    returns (uint pulled)
  {
    uint amount_ = strict ? amount : token.balanceOf(fundOwner);
    if (amount_ == 0) {
      return 0;
    }
    require(TransferLib.transferTokenFrom(token, fundOwner, msg.sender, amount_), "SRL/pullFailed");
    return amount_;
  }

  /// @inheritdoc AbstractRoutingLogic
  function pushLogic(IERC20 token, address fundOwner, uint amount) public virtual override returns (uint pushed) {
    require(TransferLib.transferTokenFrom(token, msg.sender, fundOwner, amount), "SRL/pushFailed");
    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  function balanceLogic(IERC20 token, address fundOwner) public view virtual override returns (uint balance) {
    balance = token.balanceOf(fundOwner);
  }
}