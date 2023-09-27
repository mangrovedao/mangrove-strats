// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {Permit2TransferLib} from "./Permit2TransferLib.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";

enum ApprovalType {
  NormalTransfer,
  Permit2TransferOneTime,
  Permit2Transfer
}

struct ApprovalInfo {
  ApprovalType approvalType;
  ISignatureTransfer.PermitTransferFrom permitTransferFrom;
  IAllowanceTransfer.PermitSingle permit;
  bytes signature;
  IPermit2 permit2;
}

///@title This library helps interact with different kind of approvals.
library ApprovalTransferLib {
  function transferWithApprovalInfo(
    IERC20 token,
    address from,
    address to,
    uint amount,
    ApprovalInfo calldata approvalInfo
  ) public returns (uint transferred) {
    if (approvalInfo.approvalType == ApprovalType.NormalTransfer) {
      if (TransferLib.transferTokenFrom(token, from, to, amount)) {
        return amount;
      } else {
        return 0;
      }
    } else if (approvalInfo.approvalType == ApprovalType.Permit2TransferOneTime) {
      if (
        Permit2TransferLib.transferTokenFromWithPermit2Signature(
          approvalInfo.permit2, from, to, amount, approvalInfo.permitTransferFrom, approvalInfo.signature
        )
      ) {
        return amount;
      } else {
        return 0;
      }
    } else if (approvalInfo.approvalType == ApprovalType.Permit2Transfer) {
      approvalInfo.permit2.permit(from, approvalInfo.permit, approvalInfo.signature);
      if (Permit2TransferLib.transferTokenFromWithPermit2(approvalInfo.permit2, token, from, to, amount)) {
        return amount;
      } else {
        return 0;
      }
    }
  }
}
