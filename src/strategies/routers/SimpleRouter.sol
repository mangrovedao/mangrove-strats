// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter, RL} from "./abstract/AbstractRouter.sol";

///@title `SimpleRouter` instances have a unique sourcing strategy: pull (push) liquidity directly from (to) the an offer owner's account
///@dev Maker contracts using this router must make sure that the `routingOrder.PROXY_OWNER` approves the router for all asset that will be pulled (outbound tokens)
/// Thus a maker contract using a vault that is not an EOA must make sure this vault has approval capacities.
contract SimpleRouter is AbstractRouter {
  /// @inheritdoc AbstractRouter
  function __pull__(RL.RoutingOrder memory routingOrder, bool strict) internal virtual override returns (uint pulled) {
    // if not strict, pulling all available tokens from reserve
    uint amount = strict ? routingOrder.amount : routingOrder.token.balanceOf(routingOrder.PROXY_OWNER);
    if (TransferLib.transferTokenFrom(routingOrder.token, routingOrder.PROXY_OWNER, msg.sender, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  /// @inheritdoc AbstractRouter
  function __push__(RL.RoutingOrder memory routingOrder) internal virtual override returns (uint) {
    bool success =
      TransferLib.transferTokenFrom(routingOrder.token, msg.sender, routingOrder.PROXY_OWNER, routingOrder.amount);
    return success ? routingOrder.amount : 0;
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(RL.RoutingOrder calldata routingOrder) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    uint allowance = routingOrder.token.allowance(routingOrder.PROXY_OWNER, address(this));
    require(allowance >= type(uint96).max || allowance >= routingOrder.amount, "SimpleRouter/InsufficientlyApproved");
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(RL.RoutingOrder calldata routingOrder) public view virtual override returns (uint balance) {
    balance = routingOrder.token.balanceOf(routingOrder.PROXY_OWNER);
  }
}
