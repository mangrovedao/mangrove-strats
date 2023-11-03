// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter} from "./abstract/AbstractRouter.sol";

///@title SimpleRouter - routes liquidity to and from owner which must be encoded and passed to pull and push function
contract SimpleRouter is AbstractRouter {
  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @dev pulldData is a bytes array that holds the owner address and a boolean indicating if the pull should be strict.
  /// @inheritdoc AbstractRouter
  function __pull__(IERC20 token, uint amount, bytes memory packedStrictOwner)
    internal
    virtual
    override
    returns (uint pulled)
  {
    // if not strict, pulling all available tokens from reserve
    (bool strict, address owner) = abi.decode(packedStrictOwner, (bool, address));
    amount = strict ? amount : token.balanceOf(owner);
    if (TransferLib.transferTokenFrom(token, owner, msg.sender, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  /// @notice transfers an amount of tokens from the maker to the reserve.
  /// @dev pushData is a bytes array that holds the owner address.
  /// @inheritdoc AbstractRouter
  function __push__(IERC20 token, uint amount, bytes memory encodedOwner) internal override returns (uint) {
    address owner = abi.decode(encodedOwner, (address));
    bool success = TransferLib.transferTokenFrom(token, msg.sender, owner, amount);
    return success ? amount : 0;
  }

  ///@inheritdoc AbstractRouter
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  function __checkList__(IERC20 token, bytes calldata encodedOwner) internal view override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    require(token.allowance(abi.decode(encodedOwner, (address)), address(this)) > 0, "SimpleRouter/NotApprovedByOwner");
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, bytes calldata encodedOwner) public view override returns (uint balance) {
    balance = token.balanceOf(abi.decode(encodedOwner, (address)));
  }
}
