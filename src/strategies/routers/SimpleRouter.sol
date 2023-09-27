// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Permit2TransferLib} from "mgv_strat_src/strategies/utils/Permit2TransferLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AbstractRouter, ApprovalInfo, TransferType} from "./abstract/AbstractRouter.sol";
import {MonoRouter} from "./abstract/MonoRouter.sol";

///@title `SimpleRouter` instances have a unique sourcing strategy: pull (push) liquidity directly from (to) the an offer owner's account
///@dev Maker contracts using this router must make sure that the reserve approves the router for all asset that will be pulled (outbound tokens)
/// Thus a maker contract using a vault that is not an EOA must make sure this vault has approval capacities.
contract SimpleRouter is MonoRouter {
  constructor(IPermit2 _permit2) MonoRouter(_permit2, address(_permit2) == address(0) ? 70_000 : 74_000) {}

  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @param token Token to be transferred
  /// @param owner The account from which the tokens will be transferred.
  /// @param amount The amount of tokens to be transferred
  /// @param strict wether the caller maker contract wishes to pull at most `amount` tokens of owner.
  /// @return pulled The amount pulled if successful (will be equal to `amount`); otherwise, 0.
  /// @dev requires approval from `owner` for `this` to transfer `token`.
  function __pull__(IERC20 token, address owner, uint amount, bool strict, ApprovalInfo calldata approvalInfo)
    internal
    virtual
    override
    returns (uint pulled)
  {
    // if not strict, pulling all available tokens from reserve
    amount = strict ? amount : token.balanceOf(owner);

    if (approvalInfo.transferType == TransferType.NormalTransfer) {
      if (TransferLib.transferTokenFrom(token, owner, msg.sender, amount)) {
        return amount;
      } else {
        return 0;
      }
    } else if (approvalInfo.transferType == TransferType.Permit2TransferOneTime) {
      if (
        Permit2TransferLib.transferTokenFromWithPermit2Signature(
          permit2, owner, msg.sender, amount, approvalInfo.permitTransferFrom, approvalInfo.signature
        )
      ) {
        return amount;
      } else {
        return 0;
      }
    } else if (approvalInfo.transferType == TransferType.Permit2Transfer) {
      if (Permit2TransferLib.transferTokenFromWithPermit2(permit2, token, owner, msg.sender, amount)) {
        return amount;
      } else {
        return 0;
      }
    }
  }

  /// @notice transfers an amount of tokens from the maker to the reserve.
  /// @inheritdoc AbstractRouter
  function __push__(IERC20 token, address owner, uint amount) internal virtual override returns (uint) {
    bool success = TransferLib.transferTokenFrom(token, msg.sender, owner, amount);
    return success ? amount : 0;
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address owner) public view override returns (uint) {
    return token.balanceOf(owner);
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
