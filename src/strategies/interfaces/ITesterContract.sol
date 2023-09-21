// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.0;

import {ILiquidityProvider} from "./ILiquidityProvider.sol";
import {OLKey} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title Interface for testing Forwarder and Direct maker contracts with reserve setters.
interface ITesterContract is ILiquidityProvider {
  function tokenBalance(IERC20 token, address reserveId) external view returns (uint);

  function newOfferFromVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq)
    external
    payable
    returns (uint offerId);

  function updateOfferFromVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq)
    external
    payable;
}
