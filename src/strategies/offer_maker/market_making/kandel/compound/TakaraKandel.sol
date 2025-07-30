// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./CompoundKandel.sol";
import {TakaraLendRouter} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";

contract TakaraKandel is CompoundKandel {
  /// @notice Constructor
  /// @param mgv The Mangrove deployment.
  /// @param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  /// @param gasreq the gas required by the strat to execute
  /// @param routerParams routing policy parameters for this contract
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, RouterParams memory routerParams)
    CompoundKandel(mgv, olKeyBaseQuote, gasreq, routerParams)
  {}

  /// @notice Claims rewards for the base and quote tokens
  /// @dev Only callable by the admin
  function claimReward() public onlyAdmin {
    TakaraLendRouter(address(router())).claimReward(address(BASE));
    TakaraLendRouter(address(router())).claimReward(address(QUOTE));
  }
}
