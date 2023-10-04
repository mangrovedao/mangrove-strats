// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {ISignatureTransfer} from "mgv_strat_lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "mgv_strat_lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {Permit2TransferLib} from "./Permit2TransferLib.sol";
import {IERC20} from "mgv_src/core/MgvLib.sol";
import {IPermit2} from "mgv_strat_lib/permit2/src/interfaces/IPermit2.sol";

enum ApprovalType {
  ERC20Approval,
  Permit2ApprovalOneTime,
  Permit2Approval
}

struct ApprovalInfo {
  ApprovalType approvalType;
  ISignatureTransfer.PermitTransferFrom permitTransferFrom;
  IAllowanceTransfer.PermitSingle permit;
  bytes signature;
  IPermit2 permit2;
}

///@title The purpose of this library is to help interact with different kinds of approvals when transferring tokens between addresses.
library ApprovalTransferLib {
  ///@notice This function is designed to facilitate token transfers between addresses while considering different types of approval mechanisms. It takes into account a set of parameters and approval information to determine how the transfer should be executed.
  ///@param token An interface to an ERC-20 token contract representing the token to be transferred.
  ///@param from The address from which tokens will be transferred.
  ///@param to The address to which tokens will be transferred.
  ///@param amount The amount of tokens to be transferred.
  ///@param approvalInfo An approvalInfo structure containing information about the approval. This structure includes details about the type of approval, permit data, and a signature for verification.
  ///@return success true if transfer was successful; otherwise, false.
  function transferWithApprovalInfo(
    IERC20 token,
    address from,
    address to,
    uint amount,
    ApprovalInfo calldata approvalInfo
  ) public returns (bool success) {
    if (approvalInfo.approvalType == ApprovalType.NormalApproval) {
      return TransferLib.transferTokenFrom(token, from, to, amount);
    } else if (approvalInfo.approvalType == ApprovalType.Permit2ApprovalOneTime) {
      return Permit2TransferLib.transferTokenFromWithPermit2Signature(
        approvalInfo.permit2, from, to, amount, approvalInfo.permitTransferFrom, approvalInfo.signature
      );
    } else if (approvalInfo.approvalType == ApprovalType.Permit2Approval) {
      return Permit2TransferLib.transferTokenFromWithPermit2(
        approvalInfo.permit2, token, from, to, amount, approvalInfo.permit, approvalInfo.signature
      );
    }
  }
}
