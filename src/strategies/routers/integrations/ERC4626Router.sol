// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {TransferLib2} from "@mgv-strats/src/strategies/utils/TransferLib2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626 Router
/// @notice A router that interacts with ERC4626 vaults
contract ERC4626Router is AbstractRouter {
  /// @notice Emitted when the admin withdraws tokens
  /// @param token The token being withdrawn
  /// @param amount The amount of tokens being withdrawn
  /// @param recipient The recipient of the tokens
  event AdminTokenWithdrawal(IERC20 token, uint amount, address recipient);

  /// @notice Emitted when the admin withdraws native tokens
  /// @param amount The amount of native tokens being withdrawn
  /// @param recipient The recipient of the native tokens
  event AdminNativeWithdrawal(uint amount, address recipient);

  /// @notice Emitted when a vault is set for a token
  /// @param token The token for which the vault is set
  /// @param oldVault The previous vault for the token
  /// @param newVault The new vault for the token
  event VaultSet(IERC20 indexed token, IERC4626 indexed oldVault, IERC4626 indexed newVault);

  /// @notice Mapping of tokens to their corresponding vaults
  mapping(IERC20 => IERC4626) public vaults;

  /// @notice Withdraws tokens from the router
  /// @param token The token to withdraw
  /// @param amount The amount of tokens to withdraw
  /// @return The amount of tokens withdrawn
  function withdraw(IERC20 token, uint amount) external onlyBound returns (uint) {
    RL.RoutingOrder memory routingOrder = RL.createOrder({fundOwner: msg.sender, token: token});
    return __pull__(routingOrder, amount, true);
  }

  /// @notice Pushes tokens to the router and deposits them into the vault
  /// @param token0 The first token to push and deposit
  /// @param amount0 The amount of the first token to push and deposit
  /// @param token1 The second token to push and deposit
  /// @param amount1 The amount of the second token to push and deposit
  /// @return pushed0 The amount of the first token pushed and deposited
  /// @return pushed1 The amount of the second token pushed and deposited
  function pushAndDeposit(IERC20 token0, uint amount0, IERC20 token1, uint amount1)
    external
    onlyBound
    returns (uint pushed0, uint pushed1)
  {
    if (address(token0) != address(0)) {
      pushed0 = __push__(RL.createOrder({fundOwner: msg.sender, token: token0}), amount0);
      _deposit(token0, 0);
    }
    if (address(token1) != address(0)) {
      pushed1 = __push__(RL.createOrder({fundOwner: msg.sender, token: token1}), amount1);
      _deposit(token1, 0);
    }
  }

  /// @notice Allows the admin to withdraw tokens
  /// @param base The base token
  /// @param quote The quote token
  /// @param token The token to withdraw
  /// @param amount The amount of tokens to withdraw
  /// @param recipient The recipient of the tokens
  function adminWithdrawTokens(IERC20 base, IERC20 quote, IERC20 token, uint amount, address recipient)
    external
    onlyAdmin
  {
    require(token != base && token != quote, "ERC4626Router/InvalidUnderlyingToken");
    require(
      address(token) != address(vaults[base]) && address(token) != address(vaults[quote]),
      "ERC4626Router/InvalidERC4626Token"
    );

    require(TransferLib.transferToken(token, recipient, amount), "ERC4626Router/adminWithdrawFailed");
    emit AdminTokenWithdrawal(token, amount, recipient);
  }

  /// @notice Allows the admin to withdraw native tokens
  /// @param amount The amount of native tokens to withdraw
  /// @param recipient The recipient of the native tokens
  function adminWithdrawNative(uint amount, address recipient) public onlyAdmin {
    (bool s,) = recipient.call{value: amount}("");
    require(s, "ERC4626Router/adminWithdrawNativeFailed");
    emit AdminNativeWithdrawal(amount, recipient);
  }

  /// @notice Sets the vault for a specific token
  /// @param token The token for which to set the vault
  /// @param vault The vault to set for the token
  /// @param minAssetsOut The minimum amount of assets that must be returned when withdrawing from th old vault
  /// @param minSharesOut The minimum amount of shares that must be returned when depositing into the new vault
  /// @dev Only callable by the admin
  function setVaultForToken(IERC20 token, IERC4626 vault, uint minAssetsOut, uint minSharesOut)
    public
    virtual
    onlyAdmin
  {
    // Verify token is not zero address
    require(address(token) != address(0), "ERC4626Router/zeroToken");
    require(address(token) == vault.asset(), "ERC4626Router/invalidVault");

    // If there was a previous vault, withdraw all assets
    IERC4626 oldVault = vaults[token];
    if (address(oldVault) != address(0)) {
      uint shares = oldVault.balanceOf(address(this));
      if (shares > 0) {
        uint maxRedeemable = oldVault.maxRedeem(address(this));
        require(maxRedeemable >= shares, "ERC4626Router/maxRedeemExceeded");
        uint balanceBefore = token.balanceOf(address(this));
        oldVault.redeem(shares, address(this), address(this));
        uint balanceAfter = token.balanceOf(address(this));
        require(balanceAfter - balanceBefore >= minAssetsOut, "ERC4626Router/insufficientAssets");
      }
    }

    // Set the new vault
    vaults[token] = vault;
    // Emit event for vault change
    emit VaultSet(token, oldVault, vault);
    // Redeposit token
    _deposit(token, minSharesOut);
  }

  /// @notice Gets the balance of a token
  /// @param routingOrder The routing order
  /// @return balance The balance of the token
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint balance) {
    balance = _tokenBalance(routingOrder.token);
  }

  /// @notice Gets the balance of a token, including both local balance and assets in vaults
  /// @dev Returns the sum of direct token balance and assets in vaults, already accounting for vault fees
  /// @param token The token to get the balance of
  /// @return balance The balance of the token
  function _tokenBalance(IERC20 token) public view returns (uint balance) {
    balance = token.balanceOf(address(this));
    IERC4626 vault = vaults[token];
    if (address(vault) != address(0)) {
      balance += vault.previewRedeem(vault.balanceOf(address(this)));
    }
  }

  /// @notice Deposits tokens into the vault
  /// @param token The token to deposit
  function _deposit(IERC20 token, uint minSharesOut) internal {
    IERC4626 vault = vaults[token];
    if (address(vault) != address(0)) {
      uint balance = token.balanceOf(address(this));
      if (balance > 0) {
        uint maxDeposit = vault.maxDeposit(address(this));
        uint toDeposit = maxDeposit < balance ? maxDeposit : balance;
        require(TransferLib2.forceApproveToken(token, address(vault), toDeposit), "ERC4626Router/depositFailed");
        uint balanceBefore = vault.balanceOf(address(this));
        vault.deposit(toDeposit, address(this));
        uint balanceAfter = vault.balanceOf(address(this));
        require(balanceAfter - balanceBefore >= minSharesOut, "ERC4626Router/insufficientShares");
      }
    }
    // if no vault found don't do anything
  }

  /// @notice Pushes tokens to the router
  /// @param routingOrder The routing order
  /// @param amount The amount of tokens to push
  /// @return pushedAmount The amount of tokens pushed
  /// NOTE: This function does NOT support fee-on-transfer tokens
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal override returns (uint pushedAmount) {
    require(
      TransferLib.transferTokenFrom(routingOrder.token, routingOrder.fundOwner, address(this), amount),
      "ERC4626Router/pushFailed"
    );
    return amount;
  }

  /// @notice Pulls tokens from the router
  /// @param routingOrder The routing order
  /// @param amount The amount of tokens to pull
  /// @param strict Whether to pull strictly
  /// @return pulledAmount The amount of tokens pulled
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict)
    internal
    override
    returns (uint pulledAmount)
  {
    IERC4626 vault = vaults[routingOrder.token];
    uint localBalance = routingOrder.token.balanceOf(address(this));

    if (localBalance >= amount) {
      require(TransferLib.transferToken(routingOrder.token, msg.sender, amount), "ERC4626Router/transferFailed");
      return amount;
    }

    if (address(vault) == address(0)) revert("ERC4626Router/insufficientFunds");

    if (amount == type(uint).max) {
      // Redeem all shares if max amount requested
      uint shares = vault.maxRedeem(address(this));
      uint amountWithdrawn;
      if (shares > 0) {
        amountWithdrawn = vault.redeem(shares, msg.sender, address(this));
      }
      if (localBalance > 0) {
        require(TransferLib.transferToken(routingOrder.token, msg.sender, localBalance), "ERC4626Router/transferFailed");
      }
      return localBalance + amountWithdrawn;
    }

    uint toWithdraw = amount - localBalance;

    vault.withdraw(toWithdraw, msg.sender, address(this));
    require(TransferLib.transferToken(routingOrder.token, msg.sender, localBalance), "ERC4626Router/transferFailed");

    return amount;
  }
}
