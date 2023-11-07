// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {RoutingOrderLib as RL} from "./RoutingOrderLib.sol";

/// @title AbstractRouter
/// @notice Partial implementation and requirements for liquidity routers.

abstract contract AbstractRouter is AccessControlled(msg.sender) {
  ///@notice the bound maker contracts which are allowed to call this router.
  mapping(address => bool) internal boundMakerContracts;

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
    return boundMakerContracts[mkr];
  }

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param routingOrder the arguments of the pull order
  ///@return pulled the amount of `routingOrder.token` that has been sent to `msg.sender`
  function pull(RL.RoutingOrder calldata routingOrder, bool strict) external onlyBound returns (uint pulled) {
    if (strict && routingOrder.amount == 0) {
      return 0;
    }
    pulled = __pull__(routingOrder, strict);
  }

  ///@notice router dependent hook to customize pull orders.
  ///@param routingOrder the arguments of the pull order
  ///@return pulled the amount of `routingOrder.token` that has been sent to `msg.sender`
  function __pull__(RL.RoutingOrder memory routingOrder, bool strict) internal virtual returns (uint);

  ////@notice pushes liquidity from msg.sender to the reserve
  ///@param routingOrder the arguments of the push order
  ///@return pushed the amount of `routingOrder.token` that has been taken from `msg.sender`
  function push(RL.RoutingOrder calldata routingOrder) external onlyBound returns (uint pushed) {
    if (routingOrder.amount == 0) {
      return 0;
    }
    pushed = __push__(routingOrder);
  }

  ///@notice router dependent hook to customize pull orders.
  ///@param routingOrder the arguments of the pull order
  ///@return pushed the amount of `routingOrder.token` that has been sent to `msg.sender`
  function __push__(RL.RoutingOrder memory routingOrder) internal virtual returns (uint pushed);

  ///@notice iterative `push` routing orders for the whole balance
  ///@param routingOrders to be executed
  function flush(RL.RoutingOrder[] memory routingOrders) external onlyBound {
    for (uint i = 0; i < routingOrders.length; ++i) {
      routingOrders[i].amount = routingOrders[i].token.balanceOf(msg.sender);
      if (routingOrders[i].amount > 0) {
        require(__push__(routingOrders[i]) == routingOrders[i].amount, "router/pushFailed");
      }
    }
  }

  ///@notice adds a maker contract address to the allowed makers of this router
  ///@dev this function is callable by router's admin to bootstrap, but later on an allowed maker contract can add another address
  ///@param makerContract the maker contract address
  function bind(address makerContract) public onlyAdmin {
    boundMakerContracts[makerContract] = true;
    emit MakerBind(makerContract);
  }

  ///@notice removes a maker contract address from the allowed makers of this router
  ///@param makerContract the maker contract address
  function _unbind(address makerContract) internal {
    boundMakerContracts[makerContract] = false;
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

  ///@notice verifies whether a routing order is executable on the current state
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param routingOrder to be checked
  function checkList(RL.RoutingOrder calldata routingOrder) external view {
    require(isBound(msg.sender), "Router/callerIsNotBoundToRouter");
    // checking maker contract has approved this for token transfer (in order to push to reserve)
    uint allowance = routingOrder.token.allowance(msg.sender, address(this));
    require(allowance >= type(uint96).max || allowance >= routingOrder.amount, "Router/NotApprovedByMakerContract");
    // pulling on behalf of `reserveId` might require a special approval (e.g if `reserveId` is some account on a protocol).
    __checkList__(routingOrder);
  }

  ///@notice router-dependent additional checks
  ///@param routingOrder to be checked
  function __checkList__(RL.RoutingOrder calldata routingOrder) internal view virtual;

  ///@notice performs necessary approval to activate router for a give routing order
  ///@param routingOrder to be activated
  function activate(RL.RoutingOrder calldata routingOrder) external boundOrAdmin {
    __activate__(routingOrder);
  }

  ///@notice router-dependent implementation of the `activate` function
  ///@param routingOrder to be activated
  function __activate__(RL.RoutingOrder calldata routingOrder) internal virtual {
    routingOrder; //ssh
  }

  ///@notice Computes how much funds are available for a given pull routing order
  ///@param routingOrder the pull order
  ///@return balance that is accessible to the router for `routingOrder.token`
  ///@dev `routingOrder.amount` is ignored.
  function balanceOfReserve(RL.RoutingOrder calldata routingOrder) public view virtual returns (uint balance);
}
