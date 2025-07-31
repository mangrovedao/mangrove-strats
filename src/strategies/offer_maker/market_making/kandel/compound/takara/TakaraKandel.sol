// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CompoundKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundKandel.sol";
import {TakaraRouter} from "@mgv-strats/src/strategies/routers/integrations/TakaraRouter.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";

contract TakaraKandel is CompoundKandel {
  /// @notice Constructor
  /// @param mgv The Mangrove deployment.
  /// @param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  /// @param gasreq the gas required by the strat to execute
  /// @param routerParams routing policy parameters for this contract
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, RouterParams memory routerParams)
    CompoundKandel(mgv, olKeyBaseQuote, gasreq, routerParams)
  {}

  function claimReward() external onlyAdmin {
    TakaraRouter(address(router())).claimReward();
  }
}
