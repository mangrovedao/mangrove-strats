// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter} from "./abstract/AbstractRouter.sol";

contract SimpleRouter is AbstractRouter {
  /// @notice Pull Structure for `SimpleRouter`
  /// @param owner the owner of the offer
  /// @param strict if true, the router will pull exactly `amount` tokens from the reserve.
  struct PullStruct {
    address owner;
    bool strict;
  }

  /// @notice Push Structure for `SimpleRouter`
  /// @param owner the owner of the offer
  struct PushStruct {
    address owner;
  }

  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @dev pulldData is a bytes array that holds the owner address and a boolean indicating if the pull should be strict.
  /// @inheritdoc AbstractRouter
  function __pull__(IERC20 token, uint amount, bytes memory pullData) internal virtual override returns (uint pulled) {
    // if not strict, pulling all available tokens from reserve
    PullStruct memory p = abi.decode(pullData, (PullStruct));
    amount = p.strict ? amount : token.balanceOf(p.owner);
    if (TransferLib.transferTokenFrom(token, p.owner, msg.sender, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  /// @notice transfers an amount of tokens from the maker to the reserve.
  /// @dev pushData is a bytes array that holds the owner address.
  /// @inheritdoc AbstractRouter
  function __push__(IERC20 token, uint amount, bytes memory pushData) internal virtual override returns (uint) {
    PushStruct memory p = abi.decode(pushData, (PushStruct));
    bool success = TransferLib.transferTokenFrom(token, msg.sender, p.owner, amount);
    return success ? amount : 0;
  }

  ///@notice router-dependent implementation of the `checkList` function
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset whose approval must be checked
  ///@param owner the account that requires asset pulling/pushing
  function __checkList__(IERC20 token, address owner) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    require(token.allowance(owner, address(this)) > 0, "SimpleRouter/NotApprovedByOwner");
  }
}
