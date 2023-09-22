// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {Permit2TransferLib} from "mgv_strat_src/strategies/utils/Permit2TransferLib.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {MonoRouter} from "./abstract/MonoRouter.sol";

//@title `Permit2Router` instances pull (push) liquidity directly from (to) an offer owner's account using the Permit2 contract
//@dev Maker contracts using this router must make sure that the reserve approves Permit2 for all assets that will be pulled (outbound tokens), and then the user needs to either approve the router in Permit2 or use a just-in-time signature to authorize the transfer.
contract Permit2Router is MonoRouter {
  IPermit2 public permit2;

  constructor(IPermit2 _permit2) MonoRouter(74_000) {
    permit2 = _permit2;
  }

  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @param token This parameter represents the token to be transferred.
  /// @param owner This parameter determines the reserve's location, but it's specific to the router's implementation.
  /// @param amount Indicates the amount of tokens to be transferred.
  /// @param strict This parameter signifies whether the calling maker contract intends to pull a maximum of amount tokens from the owner.
  /// @return pulled The amount pulled if successful (will be equal to `amount`); otherwise, 0.
  /// @dev requires approval from `owner` for `this` to transfer `token`.
  function __pull__(IERC20 token, address owner, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint pulled)
  {
    amount = strict ? amount : token.balanceOf(owner);
    if (Permit2TransferLib.transferTokenFromWithPermit2(permit2, token, owner, msg.sender, amount)) {
      return amount;
    } else {
      return 0;
    }
  }

  /// @notice transfers an amount of tokens from the maker to the reserve.
  function __push__(IERC20 token, address owner, uint amount) internal virtual override returns (uint) {
    bool success = TransferLib.transferTokenFrom(token, msg.sender, owner, amount);
    return success ? amount : 0;
  }

  function balanceOfReserve(IERC20 token, address owner) public view override returns (uint) {
    return token.balanceOf(owner);
  }

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param token This parameter represents the token to be transferred.
  ///@param reserveId identifies the fund owner (router implementation dependent).
  ///@param amount of `token` the maker contract wishes to pull from its reserve
  ///@param strict This parameter signifies whether the calling maker contract intends to pull a maximum of amount tokens from the owner.
  ///@param permit Permit data signed over by the owner.
  ///@param signature The signature to verify.
  ///@return pulled the amount that was successfully pulled.
  function pullWithPermit2(
    IERC20 token,
    address reserveId,
    uint amount,
    bool strict,
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) external onlyBound returns (uint pulled) {
    if (strict && amount == 0) {
      return 0;
    }
    amount = strict ? amount : token.balanceOf(reserveId);
    if (
      Permit2TransferLib.transferTokenFromWithPermit2Signature(
        permit2, reserveId, msg.sender, amount, permit, signature
      )
    ) {
      return amount;
    } else {
      return 0;
    }
  }

  ///@notice router-dependent implementation of the `checkList` function
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset whose approval must be checked
  ///@param owner the account that requires asset pulling/pushing
  function __checkList__(IERC20 token, address owner) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    require(token.allowance(owner, address(permit2)) > 0, "SimpleRouter/NotApprovedByOwner");
  }
}
