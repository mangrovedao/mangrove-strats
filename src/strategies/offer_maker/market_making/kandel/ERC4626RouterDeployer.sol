// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/ERC4626Router.sol";

/// @title Router deployer for ERC4626 integration
/// @notice This contract helps reduce the bytecode size of ERC4626KandelSeeder
/// @dev This contract is intended to be used by ERC4626KandelSeeder
contract ERC4626RouterDeployer {
  /// @notice Deploys a new ERC4626Router
  /// @return router The newly deployed ERC4626Router
  function deployRouter() external returns (ERC4626Router router) {
    router = new ERC4626Router();

    // Transfer admin rights to the specified address
    router.setAdmin(msg.sender);
  }
}
