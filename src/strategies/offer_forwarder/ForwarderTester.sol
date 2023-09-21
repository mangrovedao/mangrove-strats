// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OfferForwarder, IMangrove, AbstractRouter} from "./OfferForwarder.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {ITesterContract} from "mgv_strat_src/strategies/interfaces/ITesterContract.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";

contract ForwarderTester is OfferForwarder, ITesterContract {
  constructor(IMangrove mgv, address deployer) OfferForwarder(mgv, deployer) {}

  function tokenBalance(IERC20 token, address owner) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_.balanceOfReserve(token, owner);
  }

  function internal_addOwner(bytes32 olKeyHash, uint offerId, address owner, uint leftover) external {
    addOwner(olKeyHash, offerId, owner, leftover);
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

  function newOfferFromVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq)
    external
    payable
    returns (uint offerId)
  {
    int logPrice = LogPriceConversionLib.logPriceFromVolumes(wants, gives);
    return newOffer(olKey, logPrice, gives, gasreq);
  }

  function updateOfferFromVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq)
    external
    payable
  {
    int logPrice = LogPriceConversionLib.logPriceFromVolumes(wants, gives);
    updateOffer(olKey, logPrice, gives, offerId, gasreq);
  }
}
