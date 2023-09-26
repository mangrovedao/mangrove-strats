// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import "mgv_strat_src/strategies/offer_forwarder/OfferForwarder.sol";
import "mgv_strat_src/strategies/routers/SimpleRouter.sol";

contract OasisLike is OfferForwarder {
  bytes32 public constant NAME = "OasisLike";

  constructor(IPermit2 permit2, IMangrove mgv, address deployer) OfferForwarder(permit2, mgv, deployer) {}
}
