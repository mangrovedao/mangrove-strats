// SPDX-License-Identifier:	MIT
pragma solidity ^0.8.10;

import {ILiquidityProvider} from "@mgv-strats/src/strategies/interfaces/ILiquidityProvider.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

///@title Interface for testing Forwarder and Direct maker contracts a unifying balance view function

interface ITesterContract is ILiquidityProvider {
  ///@notice asset balance available to the contract
  ///@param token the asset whose balance is required
  function tokenBalance(IERC20 token, address reserveId) external view returns (uint);

  ///@notice new offer using wants and gives to get the price tick
  ///@param olKey offer list key
  ///@param wants how much inbound tokens maker wants
  ///@param gives how much outbound tokens maker promises
  ///@param gasreq gas required to execute offer
  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq)
    external
    payable
    returns (uint offerId);

  ///@notice update offer using wants and gives to get the price tick
  ///@param olKey offer list key
  ///@param wants how much inbound tokens maker wants
  ///@param gives how much outbound tokens maker promises
  ///@param offerId offer identifier
  ///@param gasreq gas required to execute offer
  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq) external payable;
}
