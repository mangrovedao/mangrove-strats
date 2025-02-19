// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC4626Router.sol";
import {IMorphoFactory} from "../../interfaces/IMorphoFactory.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

/// @title MorphoVaultRouter
/// @notice Router for interacting with Morpho vaults implementing ERC4626
contract MorphoVaultRouter is ERC4626Router {
  IMorphoFactory public immutable MORPHO_FACTORY;

  constructor(IMorphoFactory factory) ERC4626Router() {
    MORPHO_FACTORY = factory;
  }

  function setVaultForToken(IERC20 token, IERC4626 vault) external override onlyAdmin {
    require(MORPHO_FACTORY.isMorphoVault(address(vault)), "MorphoRouter/notMorpho");
    vaults[token] = vault;
  }
}
