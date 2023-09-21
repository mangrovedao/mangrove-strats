// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";

///@title This library helps with safely interacting with Permit2 contract
///@notice Transferring 0 or to self will be skipped.
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
    if (spender == recipient) {
      return token.balanceOf(spender) >= amount;
    }

    (bool success,) = address(permit2).call(
      abi.encodeWithSignature(
        "transferFrom(address,address,uint160,address)",
        address(spender),
        address(recipient),
        uint160(amount),
        address(token)
      )
    );
    return success;
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
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    if (spender == recipient) {
      return IERC20(permit.permitted.token).balanceOf(spender) >= amount;
    }

    (bool success,) = address(permit2).call(
      abi.encodeWithSignature(
        "permitTransferFrom(((address,uint256),uint256,uint256),(address,uint256),address,bytes)",
        permit,
        ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}),
        spender,
        signature
      )
    );
    return success;
  }
}
