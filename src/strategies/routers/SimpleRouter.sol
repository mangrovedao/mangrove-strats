// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter, RL} from "./abstract/AbstractRouter.sol";

///@title `SimpleRouter` instances have a unique sourcing strategy: pull (push) liquidity directly from (to) the an offer owner's account
///@dev Maker contracts using this router must make sure that the `routingOrder.fundOwner` approves the router for all asset that will be pulled (outbound tokens)
/// Thus a maker contract using a vault that is not an EOA must make sure this vault has approval capacities.
contract SimpleRouter is AbstractRouter {
  /// @inheritdoc AbstractRouter
  /// @notice SimpleRouter disregards `routingOrder.olKeyHash` and `routingOrder.offerId` as all offers are routed directly to the fund owner.
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint pulled)
  {
    // if not strict, pulling all available tokens from reserve
    uint amount_ = strict ? amount : routingOrder.token.balanceOf(routingOrder.fundOwner);
    if (TransferLib.transferTokenFrom(routingOrder.token, routingOrder.fundOwner, msg.sender, amount_)) {
      return amount_;
    } else {
      return 0;
    }
  }

  /// @inheritdoc AbstractRouter
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal virtual override returns (uint) {
    bool success = TransferLib.transferTokenFrom(routingOrder.token, msg.sender, routingOrder.fundOwner, amount);
    return success ? amount : 0;
  }

  ///@inheritdoc AbstractRouter
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view virtual override returns (uint balance) {
    balance = routingOrder.token.balanceOf(routingOrder.fundOwner);
  }
}
