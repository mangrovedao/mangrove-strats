// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OfferForwarder, IMangrove, AbstractRouter} from "./OfferForwarder.sol";
import {MgvLib, OLKey} from "mgv_src/core/MgvLib.sol";
import {IERC20} from "mgv_lib/IERC20.sol";
import {ITesterContract} from "mgv_strat_src/toy_strategies/interfaces/ITesterContract.sol";
import {Tick, TickLib} from "mgv_lib/core/TickLib.sol";

contract ForwarderTester is OfferForwarder, ITesterContract {
  constructor(IMangrove mgv, address deployer) OfferForwarder(mgv, deployer) {}

  function tokenBalance(IERC20 token, address owner) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_.balanceOfReserve(token, owner);
  }

  function internal_addOwner(bytes32 olKeyHash, uint offerId, address owner, uint leftover, bool usePermit2) external {
    addOwner(olKeyHash, offerId, owner, leftover, usePermit2);
  }

  function internal__put__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __put__(amount, order);
  }

  function internal__get__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __get__(amount, order);
  }

  function internal__posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    external
    returns (bytes32)
  {
    return __posthookFallback__(order, result);
  }

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, bool usePermit2)
    external
    payable
    returns (uint offerId)
  {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    return newOffer(olKey, tick, gives, gasreq, usePermit2);
  }

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq, bool usePermit2)
    external
    payable
  {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    updateOffer(olKey, tick, gives, offerId, gasreq, usePermit2);
  }
}
