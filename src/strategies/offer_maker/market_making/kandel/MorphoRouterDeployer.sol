// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MorphoVaultRouter, ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/MorphoVaultRouter.sol";
import {IMorphoFactory} from "../../../interfaces/IMorphoFactory.sol";
import {IMorphoRewardDistributor} from "../../../interfaces/IMorphoRewardDistributor.sol";

/// @title Router deployer for Morpho integration
/// @notice This contract helps reduce the bytecode size of MorphoKandelSeeder
/// @dev This contract is intended to be used by MorphoKandelSeeder
contract MorphoRouterDeployer {
  /// @notice Deploys a new MorphoVaultRouter
  /// @param morphoFactory The Morpho factory contract
  /// @param morphoRewardDistributor The Morpho reward distributor contract
  /// @return router The newly deployed MorphoVaultRouter
  function deployRouter(IMorphoFactory morphoFactory, IMorphoRewardDistributor morphoRewardDistributor)
    external
    returns (ERC4626Router router)
  {
    router = new MorphoVaultRouter(morphoFactory, morphoRewardDistributor);

    // Transfer admin rights to the specified address
    router.setAdmin(msg.sender);
  }
}
