// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC4626Router.sol";
import {IMorphoFactory} from "../../interfaces/IMorphoFactory.sol";
import {IMorphoRewardDistributor} from "../../interfaces/IMorphoRewardDistributor.sol";

/// @title MorphoVaultRouter
/// @notice Router for interacting with Morpho vaults implementing ERC4626
/// @title MorphoVaultRouter
/// @notice Router for interacting with Morpho vaults implementing ERC4626
contract MorphoVaultRouter is ERC4626Router {
  /// @notice The Morpho factory contract
  IMorphoFactory public immutable MORPHO_FACTORY;

  /// @notice The Morpho reward distributor contract
  IMorphoRewardDistributor public immutable MORPHO_REWARD_DISTRIBUTOR;

  /// @dev Emitted when a vault is set for a specific token
  /// @param token The token for which the vault is set
  /// @param vault The vault that is set for the token
  event VaultSet(IERC20 indexed token, IERC4626 indexed vault);

  /// @dev Emitted when rewards are claimed for a specific token
  /// @param token The token for which rewards are claimed
  /// @param amount The amount of rewards claimed
  /// @param receiver The address that receives the claimed rewards
  event RewardsClaimed(IERC20 indexed token, uint amount, address indexed receiver);

  /// @param factory The address of the Morpho factory
  /// @param distributor The address of the Morpho reward distributor
  constructor(IMorphoFactory factory, IMorphoRewardDistributor distributor) ERC4626Router() {
    MORPHO_FACTORY = factory;
    MORPHO_REWARD_DISTRIBUTOR = distributor;
  }

  /// @notice Sets the vault for a specific token
  /// @param token The token for which to set the vault
  /// @param vault The vault to set for the token
  /// @dev Only callable by the admin
  function setVaultForToken(IERC20 token, IERC4626 vault, uint minAssetsOut) public override onlyAdmin {
    require(MORPHO_FACTORY.isMorphoVault(address(vault)), "MorphoRouter/notMorpho");
    super.setVaultForToken(token, vault, minAssetsOut);
  }

  /// @notice Claims rewards for a specific token
  /// @param token The token for which to claim rewards
  /// @param amount The amount of rewards to claim
  /// @param proof The proof for claiming rewards
  /// @param receiver The address that will receive the claimed rewards
  /// @dev Only callable by the admin
  function claimRewardsForToken(IERC20 token, uint amount, bytes32[] calldata proof, address receiver)
    external
    onlyAdmin
  {
    MORPHO_REWARD_DISTRIBUTOR.claim(msg.sender, address(token), amount, proof);
    token.transfer(receiver, amount);
    emit RewardsClaimed(token, amount, receiver);
  }
}
