// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title AbstractRouter
/// @notice Partial implementation and requirements for liquidity routers.

abstract contract AbstractRoutingLogic is AccessControlled(msg.sender) {

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param token is the ERC20 managing the pulled asset
  ///@param amount of `token` the maker contract wishes to pull from its reserve
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  ///@return pulled the amount that was successfully pulled.
  function pull(IERC20 token, uint amount, bytes calldata data) external virtual returns (uint pulled) {
    pulled = __pull__({token: token, amount: amount, data: data});
  }

  ///@notice router-dependent implementation of the `pull` function
  ///@param token Token to be transferred
  ///@param amount The amount of tokens to be transferred
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  ///@return pulled The amount pulled if successful; otherwise, 0.
  function __pull__(IERC20 token, uint amount, bytes memory data) internal virtual returns (uint);

  ///@notice pushes assets from calling's maker contract to a reserve
  ///@param token is the asset the maker is pushing
  ///@param amount is the amount of asset that should be transferred from the calling maker contract
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  ///@return pushed fraction of `amount` that was successfully pushed to reserve.
  function push(IERC20 token, uint amount, bytes calldata data) external virtual returns (uint pushed) {
    if (amount == 0) {
      return 0;
    }
    pushed = __push__({token: token, amount: amount, data: data});
  }

  ///@notice router-dependent implementation of the `push` function
  ///@param token Token to be transferred
  ///@param amount The amount of tokens to be transferred
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  ///@return pushed The amount pushed if successful; otherwise, 0.
  function __push__(IERC20 token, uint amount, bytes memory data) internal virtual returns (uint pushed);

  ///@notice iterative `push` for the whole balance in a single call
  ///@param tokens to flush
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  function flush(IERC20[] calldata tokens, bytes calldata data) external virtual {
    for (uint i = 0; i < tokens.length; ++i) {
      uint amount = tokens[i].balanceOf(msg.sender);
      if (amount > 0) {
        require(__push__(tokens[i], amount, data) == amount, "router/pushFailed");
      }
    }
  }

  ///@notice allows a makerContract to verify it is ready to use `this` router for a particular reserve
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param data is a bytes array that can be used to pass arbitrary data to a specific router instance.
  function checkList(IERC20 token, bytes calldata data) external virtual view {
    // checking maker contract has approved this for token transfer (in order to push to reserve)
    require(token.allowance(msg.sender, address(this)) > 0, "Router/NotApprovedByMakerContract");
    // pulling on behalf of `reserveId` might require a special approval (e.g if `reserveId` is some account on a protocol).
    __checkList__(token, data);
  }

  ///@notice router-dependent additional checks
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  function __checkList__(IERC20 token, bytes calldata data) internal view virtual;

  ///@notice performs necessary approval to activate router function on a particular asset
  ///@param token the asset one wishes to use the router for
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  function activate(IERC20 token, bytes calldata data) external virtual {
    __activate__(token, data);
  }

  ///@notice router-dependent implementation of the `activate` function
  ///@param token the asset one wishes to use the router for
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  function __activate__(IERC20 token, bytes calldata data) internal virtual {
    token; //ssh
    data;
  }

  ///@notice Balance of a reserve
  ///@param token the asset one wishes to know the balance of
  ///@param data is a bytes array that can be used to pass arbitrary data to the router.
  ///@return balance that is accessible to the router for the given `token`
  function balanceOfReserve(IERC20 token, bytes calldata data) public view virtual returns (uint balance);
}
