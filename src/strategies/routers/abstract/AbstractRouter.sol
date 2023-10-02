// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AccessControlled} from "mgv_strat_src/strategies/utils/AccessControlled.sol";
import {IERC20} from "mgv_lib/IERC20.sol";
import {ApprovalInfo} from "mgv_strat_src/strategies/utils/ApprovalTransferLib.sol";

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

  ///@notice view for gas overhead of this router.
  ///@param reserveId that should be considered if a reserve specific route is defined.
  ///@param token that should be considered if a token specific route is defined.
  ///@return overhead the added (overapproximated) gas cost of `push` and `pull` for the routing strategy.
  function routerGasreq(IERC20 token, address reserveId) public view returns (uint overhead) {
    return __routerGasreq__(token, reserveId);
  }

  ///@notice hook that implements router specific gas requirement for a given routing strategy.
  ///@param reserveId that should be considered if a reserve specific route is defined.
  ///@param token that should be considered if a token specific route is defined.
  ///@return overhead the added (overapproximated) gas cost of `push` and `pull`.
  function __routerGasreq__(IERC20 token, address reserveId) internal view virtual returns (uint overhead);

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param token is the ERC20 managing the pulled asset
  ///@param reserveId identifies the fund owner (router implementation dependent).
  ///@param amount of `token` the maker contract wishes to pull from its reserve
  ///@param strict when the calling maker contract accepts to receive more funds from reserve than required (this may happen for gas optimization)
  ///@param approvalInfo The Approvalnfo struct that specify which approval has been made.
  ///@return pulled the amount that was successfully pulled.
  function pull(IERC20 token, address reserveId, uint amount, bool strict, ApprovalInfo calldata approvalInfo)
    external
    onlyBound
    returns (uint pulled)
  {
    if (strict && amount == 0) {
      return 0;
    }
    pulled = __pull__({token: token, reserveId: reserveId, amount: amount, strict: strict, approvalInfo: approvalInfo});
  }

  ///@notice router-dependent implementation of the `pull` function
  ///@param token Token to be transferred
  ///@param reserveId determines the location of the reserve (router implementation dependent).
  ///@param amount The amount of tokens to be transferred
  ///@param strict wether the caller maker contract wishes to pull at most `amount` tokens of owner.
  ///@param approvalInfo The Approvalnfo struct that specify which approval has been made.
  ///@return pulled The amount pulled if successful; otherwise, 0.
  function __pull__(IERC20 token, address reserveId, uint amount, bool strict, ApprovalInfo calldata approvalInfo)
    internal
    virtual
    returns (uint);

  ///@notice pushes assets from calling's maker contract to a reserve
  ///@param token is the asset the maker is pushing
  ///@param reserveId determines the location of the reserve (router implementation dependent).
  ///@param amount is the amount of asset that should be transferred from the calling maker contract
  ///@return pushed fraction of `amount` that was successfully pushed to reserve.
  function push(IERC20 token, address reserveId, uint amount) external onlyBound returns (uint pushed) {
    if (amount == 0) {
      return 0;
    }
    pushed = __push__({token: token, reserveId: reserveId, amount: amount});
  }

  ///@notice router-dependent implementation of the `push` function
  ///@param token Token to be transferred
  ///@param reserveId determines the location of the reserve (router implementation dependent).
  ///@param amount The amount of tokens to be transferred
  ///@return pushed The amount pushed if successful; otherwise, 0.
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual returns (uint pushed);

  ///@notice iterative `push` for the whole balance in a single call
  ///@param tokens to flush
  ///@param reserveId determines the location of the reserve (router implementation dependent).
  function flush(IERC20[] calldata tokens, address reserveId) external onlyBound {
    for (uint i = 0; i < tokens.length; ++i) {
      uint amount = tokens[i].balanceOf(msg.sender);
      if (amount > 0) {
        require(__push__(tokens[i], reserveId, amount) == amount, "router/pushFailed");
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

  ///@notice allows a makerContract to verify it is ready to use `this` router for a particular reserve
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param reserveId of the tokens that are being pulled
  function checkList(IERC20 token, address reserveId) external view {
    require(isBound(msg.sender), "Router/callerIsNotBoundToRouter");
    // checking maker contract has approved this for token transfer (in order to push to reserve)
    require(token.allowance(msg.sender, address(this)) > 0, "Router/NotApprovedByMakerContract");
    // pulling on behalf of `reserveId` might require a special approval (e.g if `reserveId` is some account on a protocol).
    __checkList__(token, reserveId);
  }

  ///@notice router-dependent additional checks
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param reserveId of the tokens that are being pulled
  function __checkList__(IERC20 token, address reserveId) internal view virtual;

  ///@notice performs necessary approval to activate router function on a particular asset
  ///@param token the asset one wishes to use the router for
  function activate(IERC20 token) external boundOrAdmin {
    __activate__(token);
  }

  ///@notice router-dependent implementation of the `activate` function
  ///@param token the asset one wishes to use the router for
  function __activate__(IERC20 token) internal virtual {
    token; //ssh
  }

  ///@notice Balance of a reserve
  ///@param token the asset one wishes to know the balance of
  ///@param reserveId the identifier of the reserve
  ///@return the balance of the reserve
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual returns (uint);
}
