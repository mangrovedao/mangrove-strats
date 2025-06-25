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

  /// @notice Emitted when a deposit operation occurs
  event VaultDeposit(uint assets, uint shares);

  /// @notice Emitted when a withdrawal operation occurs
  event VaultWithdraw(uint assets, uint shares);

  /// @notice Contract constructor
  /// @param vault The ERC4626 vault contract address
  constructor(IERC4626 vault) {
    VAULT = vault;
    ASSET = IERC20(vault.asset());
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Pulls tokens by withdrawing from the ERC4626 vault
  /// @param token The token to pull (must match vault's asset)
  /// @param fundOwner Not used - this contract owns the shares
  /// @param amount The amount of underlying assets to withdraw
  /// @param strict If true, must withdraw exact amount; if false, withdraw available balance
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict) external override returns (uint pulled) {
    require(address(token) == address(ASSET), "SimpleERC4626Logic/InvalidToken");

    // Convert shares to assets to see how much can be withdrawn
    uint maxWithdrawable = VAULT.maxWithdraw(address(this));

    if (maxWithdrawable == 0) {
      return 0;
    }

    // Determine withdrawal amount
    uint withdrawAmount;
    if (strict) {
      require(maxWithdrawable >= amount, "SimpleERC4626Logic/InsufficientBalance");
      withdrawAmount = amount;
    } else {
      withdrawAmount = maxWithdrawable < amount ? maxWithdrawable : amount;
    }

    if (withdrawAmount == 0) {
      return 0;
    }

    // Withdraw from vault and send assets to the calling maker contract
    uint sharesUsed = VAULT.withdraw(withdrawAmount, msg.sender, address(this));

    emit VaultWithdraw(withdrawAmount, sharesUsed);
    return withdrawAmount;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Pushes tokens by depositing into the ERC4626 vault
  /// @param token The token to push (must match vault's asset)
  /// @param fundOwner Not used - this contract receives the shares
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

    // Deposit into vault - this contract receives the shares
    uint sharesReceived = VAULT.deposit(amount, address(this));

    emit VaultDeposit(amount, sharesReceived);
    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @notice Returns the underlying asset balance available from this contract's vault shares
  /// @param token The token to check (must match vault's asset)
  /// @param fundOwner Not used - this contract owns the shares
  /// @return balance The amount of underlying assets this contract can withdraw
  function balanceLogic(IERC20 token, address fundOwner) external view override returns (uint balance) {
    require(address(token) == address(ASSET), "SimpleERC4626Logic/InvalidToken");

    uint shareBalance = VAULT.balanceOf(address(this));
    if (shareBalance == 0) {
      return 0;
    }

    // Convert shares to underlying assets
    balance = VAULT.convertToAssets(shareBalance);
  }

  /// @notice Get the vault share balance of this contract
  /// @return shares The amount of vault shares owned by this contract
  function shareBalance() external view returns (uint shares) {
    return VAULT.balanceOf(address(this));
  }

  /// @notice Preview how many shares would be received for a deposit
  /// @param assets The amount of assets to deposit
  /// @return shares The amount of shares that would be received
  function previewDeposit(uint assets) external view returns (uint shares) {
    return VAULT.previewDeposit(assets);
  }

  /// @notice Preview how many shares would be burned for a withdrawal
  /// @param assets The amount of assets to withdraw
  /// @return shares The amount of shares that would be burned
  function previewWithdraw(uint assets) external view returns (uint shares) {
    return VAULT.previewWithdraw(assets);
  }

  /// @notice Get vault information
  /// @return vault The vault address
  /// @return asset The underlying asset address
  /// @return totalAssets The total assets in the vault
  function getVaultInfo() external view returns (address vault, address asset, uint totalAssets) {
    return (address(VAULT), address(ASSET), VAULT.totalAssets());
  }
}
