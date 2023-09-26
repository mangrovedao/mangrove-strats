// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";

///@title This library helps with safely interacting with Permit2 contract
///@notice ERC20 tokens returning bool instead of reverting are handled.
library Permit2TransferLib {
  ///@notice This transfer amount of token to recipient address from spender address
  ///@param permit2 Permit2 contract
  ///@param token Token to be transferred
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function transferTokenFromWithPermit2(IPermit2 permit2, IERC20 token, address spender, address recipient, uint amount)
    internal
    returns (bool)
  {
    if (amount == 0) {
      return true;
    }
    require(uint160(amount) == amount, "Permit2TransferLib/amountIsNotUInt160");

    if (spender == recipient) {
      return token.balanceOf(spender) >= amount;
    }

    try permit2.transferFrom(address(spender), address(recipient), uint160(amount), address(token)) {
      return true;
    } catch {
      return false;
    }
  }

  ///@notice This transfer amount of token to recipient address from spender address
  ///@param permit2 Permit2 contract
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred spender, where the tokens will be transferred from
  ///@param permit The permit data signed over by the owner
  ///@param signature The signature to verify
  ///@return true if transfer was successful; otherwise, false.
  function transferTokenFromWithPermit2Signature(
    IPermit2 permit2,
    address spender,
    address recipient,
    uint amount,
    ISignatureTransfer.PermitTransferFrom memory permit,
    bytes memory signature
  ) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    require(uint160(amount) == amount, "Permit2TransferLib/amountIsNotUInt160");
    if (spender == recipient) {
      return IERC20(permit.permitted.token).balanceOf(spender) >= amount;
    }

    try permit2.permitTransferFrom(
      permit, ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}), spender, signature
    ) {
      return true;
    } catch {
      return false;
    }
  }
}
