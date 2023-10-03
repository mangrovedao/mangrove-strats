// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {OfferDispatcher, IMangrove, IERC20, AbstractRouter, Dispatcher} from "./OfferDispatcher.sol";
import {MgvLib} from "mgv_src/core/MgvLib.sol";
import {ITesterContract} from "mgv_strat_src/toy_strategies/interfaces/ITesterContract.sol";

contract OfferDispatcherTester is OfferDispatcher, ITesterContract {
  constructor(IMangrove mgv, address deployer) OfferDispatcher(mgv, deployer) {}

  function tokenBalance(IERC20 token, address owner) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_.balanceOfReserve(token, owner);
  }

  function internal_addOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, address owner, uint leftover)
    external
  {
    addOwner(outbound_tkn, inbound_tkn, offerId, owner, leftover);
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

  function getDispatcher() external view returns (Dispatcher d) {
    d = Dispatcher(address(router()));
  }
}
