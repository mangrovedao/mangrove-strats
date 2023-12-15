// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {RoutingOrderLib as RL} from "./RoutingOrderLib.sol";

/// @title AbstractRouter
/// @notice Partial implementation and requirements for liquidity routers.

abstract contract AbstractRouter is AccessControlled(msg.sender) {
  ///@notice This modifier verifies that `msg.sender` an allowed caller of this router.
  modifier onlyBound() {
    require(isBound(msg.sender), "AccessControlled/Invalid");
    _;
  }

  ///@notice This modifier verifies that `msg.sender` is the admin or an allowed caller of this router.
  modifier boundOrAdmin() {
    require(msg.sender == admin() || isBound(msg.sender), "AccessControlled/Invalid");
    _;
  }

  ///@notice logging bound maker contract
  ///@param maker the maker address. This is indexed, so that RPC calls can filter on it.
  ///@notice by emitting this data, an indexer will be able to keep track of what maker contracts are allowed to call this router.
  event MakerBind(address indexed maker);

  ///@notice logging unbound maker contract
  ///@param maker the maker address. This is indexed, so that RPC calls can filter on it.
  ///@notice by emitting this data, an indexer will be able to keep track of what maker contracts are allowed to call this router.
  event MakerUnbind(address indexed maker);

  ///@notice getter for the `makers: addr => bool` mapping
  ///@param mkr the address of a maker contract
  ///@return true if `mkr` is authorized to call this router.
  function isBound(address mkr) public view returns (bool) {
    return RL.boundMakerContracts()[mkr];
  }

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param routingOrder the arguments of the pull order
  ///@param amount of token that needs to be routed
  ///@param strict if false the router may pull at more than `amount` to msg.sender. Otherwise it pulls at least `amount`.
  ///@return pulled the amount of `routingOrder.token` that has been sent to `msg.sender`
  function pull(RL.RoutingOrder calldata routingOrder, uint amount, bool strict)
    external
    onlyBound
    returns (uint pulled)
  {
    if (strict && amount == 0) {
      return 0;
    }
    pulled = __pull__(routingOrder, amount, strict);
  }

  ///@notice router dependent hook to customize pull orders.
  ///@param routingOrder the arguments of the pull order
  ///@param amount of token that needs to be routed
  ///@param strict if false the router may pull at more than `amount` to msg.sender. Otherwise it pulls at least `amount`.
  ///@return pulled the amount of `routingOrder.token` that has been sent to `msg.sender`
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict) internal virtual returns (uint);

  ///@notice pushes liquidity from msg.sender to the reserve
  ///@param routingOrder the arguments of the push order
  ///@param amount of token that needs to be routed
  ///@return pushed the amount of `routingOrder.token` that has been taken from `msg.sender`
  function push(RL.RoutingOrder calldata routingOrder, uint amount) external onlyBound returns (uint pushed) {
    if (amount == 0) {
      return 0;
    }
    pushed = __push__(routingOrder, amount);
  }

  ///@notice router dependent hook to customize pull orders.
  ///@param routingOrder the arguments of the pull order
  ///@param amount of token that needs to be routed
  ///@return pushed the amount of `routingOrder.token` that has been sent to `msg.sender`
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal virtual returns (uint pushed);

  ///@notice iterative `push` of the whole maker contract's balance
  ///@dev minimizes external calls in case several assets needs to be pushed via the router.
  ///@param routingOrders to be executed
  function flush(RL.RoutingOrder[] memory routingOrders) external onlyBound {
    for (uint i = 0; i < routingOrders.length; ++i) {
      uint amount = routingOrders[i].token.balanceOf(msg.sender);
      if (amount > 0) {
        require(__push__(routingOrders[i], amount) == amount, "router/flushFailed");
      }
    }
  }

  ///@notice adds a maker contract address to the allowed makers of this router
  ///@dev this function is callable by router's admin to bootstrap, but later on an allowed maker contract can add another address
  ///@param makerContract the maker contract address
  function bind(address makerContract) public onlyAdmin {
    RL.boundMakerContracts()[makerContract] = true;
    emit MakerBind(makerContract);
  }

  ///@notice removes a maker contract address from the allowed makers of this router
  ///@param makerContract the maker contract address
  function _unbind(address makerContract) internal {
    RL.boundMakerContracts()[makerContract] = false;
    emit MakerUnbind(makerContract);
  }

  ///@notice removes `msg.sender` from the allowed makers of this router
  function unbind() external onlyBound {
    _unbind(msg.sender);
  }

  ///@notice removes a makerContract from the allowed makers of this router
  ///@param makerContract the maker contract address
  function unbind(address makerContract) external onlyAdmin {
    _unbind(makerContract);
  }

  /**
   * @notice Returns the token balance available for a specific routing order
   * @param routingOrder The routing order to check the balance for
   * @return balance The balance of the token in the routing order
   */
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view virtual returns (uint balance);
}
