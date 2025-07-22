// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "./abstract/AbstractRoutingLogic.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title SimpleERC4626Logic
/// @notice Routing logic for any ERC4626 vault
contract SimpleERC4626Logic is AbstractRoutingLogic {
  /// @notice The ERC4626 vault contract
  IERC4626 public immutable VAULT;

  /// @notice The underlying asset of the vault
  IERC20 public immutable ASSET;

  /// @notice Contract constructor
  /// @param vault The ERC4626 vault contract address
  constructor(IERC4626 vault) {
    VAULT = vault;
    ASSET = IERC20(vault.asset());
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Pulls tokens by withdrawing from the ERC4626 vault
  /// @param token The token to pull (must match vault's asset)
  /// @param fundOwner The owner of the shares
  /// @param amount The amount of underlying assets to withdraw
  /// @param strict If true, must withdraw exact amount; if false, withdraw available balance
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict) external override returns (uint pulled) {
    require(address(token) == address(ASSET), "SimpleERC4626Logic/InvalidToken");

    if (amount == 0) {
      return 0;
    }

    // Withdraw exact amount
    VAULT.withdraw(amount, msg.sender, fundOwner);

    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Pushes tokens by depositing into the ERC4626 vault
  /// @param token The token to push (must match vault's asset)
  /// @param fundOwner The owner of the shares
  /// @param amount The amount of assets to deposit
  function pushLogic(IERC20 token, address fundOwner, uint amount) external override returns (uint pushed) {
    require(address(token) == address(ASSET), "SimpleERC4626Logic/InvalidToken");

    if (amount == 0) {
      return 0;
    }

    // Transfer underlying assets from maker contract to this contract
    require(
      TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "SimpleERC4626Logic/AssetTransferFailed"
    );

    // Approve vault to spend the assets
    require(TransferLib.approveToken(ASSET, address(VAULT), amount), "SimpleERC4626Logic/ApprovalFailed");

    // Deposit into vault - `fundOwner` receives the shares
    VAULT.deposit(amount, fundOwner);

    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Returns the underlying asset balance available from this contract's vault shares
  /// @param token The token to check (must match vault's asset)
  /// @param fundOwner The owner of the shares
  /// @return balance The amount of underlying assets this contract can withdraw
  function balanceLogic(IERC20 token, address fundOwner) external view override returns (uint balance) {
    require(address(token) == address(ASSET), "SimpleERC4626Logic/InvalidToken");

    balance = VAULT.previewRedeem(VAULT.balanceOf(fundOwner));
  }
}
