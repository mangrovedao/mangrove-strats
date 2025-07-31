// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CompoundV2Router} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

/// @title Router deployer for Compound V2 integration
/// @notice This contract helps reduce the bytecode size of CompoundKandelSeeder
/// @dev This contract is intended to be used by CompoundKandelSeeder
contract CompoundRouterDeployer {
  /// @notice Deploys a new CompoundV2Router
  /// @return router The newly deployed CompoundV2Router
  function deployRouter() external virtual returns (AbstractRouter router) {
    router = new CompoundV2Router();

    // Transfer admin rights to the specified address
    router.setAdmin(msg.sender);
  }
}
