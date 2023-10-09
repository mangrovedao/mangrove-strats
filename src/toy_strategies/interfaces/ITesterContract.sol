// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {ILiquidityProvider} from "mgv_strat_src/strategies/interfaces/ILiquidityProvider.sol";
import {OLKey} from "mgv_src/core/MgvLib.sol";
import {IERC20} from "mgv_lib/IERC20.sol";

///@title Interface for testing Forwarder and Direct maker contracts with reserve setters.
interface ITesterContract is ILiquidityProvider {
  function tokenBalance(IERC20 token, address reserveId) external view returns (uint);

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, bool usePermit2)
    external
    payable
    returns (uint offerId);

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq, bool usePermit2)
    external
    payable;
}
