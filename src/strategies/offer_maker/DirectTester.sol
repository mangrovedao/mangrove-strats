// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IMangrove, AbstractRouter, OfferMaker, IERC20} from "./OfferMaker.sol";
import {ITesterContract} from "mgv_strat_src/strategies/interfaces/ITesterContract.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {TickLib, Tick} from "mgv_lib/TickLib.sol";

contract DirectTester is ITesterContract, OfferMaker {
  mapping(address => address) public reserves;
  bytes32 constant retdata = "lastlook/testdata";

  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, AbstractRouter router_, address deployer, uint gasreq)
    OfferMaker(mgv, router_, deployer, gasreq, deployer) // setting reserveId = deployer by default
  {}

  function tokenBalance(IERC20 token, address reserveId) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_ == NO_ROUTER ? token.balanceOf(address(this)) : router_.balanceOfReserve(token, reserveId);
  }

  function __lastLook__(MgvLib.SingleOrder calldata) internal virtual override returns (bytes32) {
    return retdata;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 maker_data)
    internal
    override
    returns (bytes32 data)
  {
    data = super.__posthookSuccess__(order, maker_data);
    require(
      data == REPOST_SUCCESS || data == COMPLETE_FILL,
      (data == "mgv/insufficientProvision")
        ? "mgv/insufficientProvision"
        : (data == "mgv/writeOffer/density/tooLow" ? "mgv/writeOffer/density/tooLow" : "posthook/failed")
    );
  }

  function newOfferFromVolume(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint gasreq
  ) external payable returns (uint offerId) {
    int tick = Tick.unwrap(TickLib.tickFromVolumes(wants, gives));
    return newOffer(outbound_tkn, inbound_tkn, tick, gives, pivotId, gasreq);
  }

  function updateOfferFromVolume(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq
  ) external payable {
    int tick = Tick.unwrap(TickLib.tickFromVolumes(wants, gives));
    updateOffer(outbound_tkn, inbound_tkn, tick, gives, pivotId, offerId, gasreq);
  }
}
