// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {BaseMangroveOrder} from "./BaseMangroveOrder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Permit2Router} from "mgv_strat_src/strategies/routers/Permit2Router.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

contract MangroveOrderWithPermit2 is BaseMangroveOrder {
  ///@notice MangroveOrderWithPermit2 is a Forwarder logic with a simple router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param permit2 The Permit2 contract
  ///@param deployer The address of the admin of `this` at the end of deployment
  ///@param gasreq The gas required for `this` to execute `makerExecute` and `makerPosthook` when called by mangrove for a resting order.
  constructor(IMangrove mgv, IPermit2 permit2, address deployer, uint gasreq)
    BaseMangroveOrder(mgv, new Permit2Router(permit2), deployer, gasreq)
  {}

  ///@notice pull inbound_tkn from the msg.sender with permit and then forward market order to MGV
  ///@param outbound_tkn outbound_tkn
  ///@param inbound_tkn inbound_tkn
  ///@param takerWants Amount of outbound_tkn taker wants
  ///@param takerGives Amount of inbound_tkn taker gives
  ///@param fillWants isBid
  ///@param permit The permit data signed over by the owner
  ///@param signature The signature to verify
  ///@return totalGot Amount of outbound_tkn received
  ///@return totalGave Amount of inbound_tkn received
  ///@return totalPenalty Penalty received
  ///@return feePaid Fee paid
  function marketOrderWithTransferApproval(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) external returns (uint totalGot, uint totalGave, uint totalPenalty, uint feePaid) {
    uint pulled = Permit2Router(address(router())).pull(inbound_tkn, msg.sender, takerGives, true, permit, signature);
    require(pulled == takerGives, "mgvOrder/transferInFail");
    (totalGot, totalGave, totalPenalty, feePaid) =
      MGV.marketOrder(address(outbound_tkn), address(inbound_tkn), takerWants, takerGives, fillWants);

    uint fund = takerGives - totalGave;
    if (fund > 0) {
      // refund the sender
      (bool noRevert,) =
        address(router()).call(abi.encodeWithSelector(router().push.selector, inbound_tkn, msg.sender, fund));
      require(noRevert, "mgvOrder/refundInboundTknFail");
    }
  }

  ///@notice call permit2 permit and then call take, this can be used to first approve and then take
  ///@param tko TakerOrder struct
  ///@param permit The permit data signed over by the owner
  ///@param signature The signature to verify
  ///@return TakerOrderResult Result of the take call
  function takeWithPermit(
    TakerOrder calldata tko,
    IAllowanceTransfer.PermitSingle memory permit,
    bytes calldata signature
  ) external payable returns (TakerOrderResult memory) {
    Permit2Router(address(router())).permit2().permit(msg.sender, permit, signature);
    return __take__(tko);
  }
}
