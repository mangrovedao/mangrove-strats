// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TakaraLendRouter, IComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";

/// @title Router deployer for Takara Lend integration
/// @notice This contract helps reduce the bytecode size of TakaraLendKandelSeeder
/// @dev This contract is intended to be used by TakaraLendKandelSeeder
contract TakaraLendRouterDeployer {
  /// @notice Deploys a new TakaraLendRouter
  /// @return router The newly deployed TakaraLendRouter
  function deployRouter(IComptroller comptroller) external virtual returns (TakaraLendRouter router) {
    router = new TakaraLendRouter(comptroller);

    // Transfer admin rights to the specified address
    router.setAdmin(msg.sender);
  }
}
