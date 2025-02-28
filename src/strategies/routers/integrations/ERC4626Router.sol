// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626 Router
/// @notice A router that interacts with ERC4626 vaults
contract ERC4626Router is AbstractRouter {
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
      _deposit(token0);
    }
    if (address(token1) != address(0)) {
      pushed1 = __push__(RL.createOrder({fundOwner: msg.sender, token: token1}), amount1);
      _deposit(token1);
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
  }

  /// @notice Allows the admin to withdraw native tokens
  /// @param amount The amount of native tokens to withdraw
  /// @param recipient The recipient of the native tokens
  function adminWithdrawNative(uint amount, address recipient) public onlyAdmin {
    (bool s,) = recipient.call{value: amount}("");
    require(s, "ERC4626Router/adminWithdrawNativeFailed");
  }

  /// @notice Sets the vault for a token
  /// @param token The token to set the vault for
  /// @param vault The vault to set
  function setVaultForToken(IERC20 token, IERC4626 vault) external virtual onlyAdmin {
    // Verify token is not zero address
    require(address(token) != address(0), "ERC4626Router/zeroToken");

    // If there was a previous vault, withdraw all assets
    IERC4626 oldVault = vaults[token];
    if (address(oldVault) != address(0)) {
      uint shares = oldVault.balanceOf(address(this));
      if (shares > 0) {
        uint maxRedeemable = oldVault.maxRedeem(address(this));
        require(maxRedeemable >= shares, "ERC4626Router/maxRedeemExceeded");
        oldVault.redeem(maxRedeemable < shares ? maxRedeemable : shares, address(this), address(this));
      }
    }

    // Set the new vault
    vaults[token] = vault;
    // Redeposit token
    _deposit(token);
  }

  /// @notice Gets the balance of a token
  /// @param routingOrder The routing order
  /// @return balance The balance of the token
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint balance) {
    balance = _tokenBalance(routingOrder.token);
  }

  /// @notice Gets the balance of a token
  /// @param token The token to get the balance of
  /// @return balance The balance of the token
  function _tokenBalance(IERC20 token) public view returns (uint balance) {
    balance = token.balanceOf(address(this));
    IERC4626 vault = vaults[token];
    if (address(vault) != address(0)) {
      balance += vault.convertToAssets(vault.balanceOf(address(this)));
    }
  }

  /// @notice Deposits tokens into the vault
  /// @param token The token to deposit
  function _deposit(IERC20 token) internal {
    IERC4626 vault = vaults[token];
    if (address(vault) != address(0)) {
      uint balance = token.balanceOf(address(this));
      if (balance > 0) {
        uint maxDeposit = vault.maxDeposit(address(this));
        uint toDeposit = maxDeposit < balance ? maxDeposit : balance;
        token.approve(address(vault), toDeposit);
        vault.deposit(toDeposit, address(this));
      }
    }
    // if not vault found dont do anything
  }

  /// @notice Pushes tokens to the router
  /// @param routingOrder The routing order
  /// @param amount The amount of tokens to push
  /// @return pushedAmount The amount of tokens pushed
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
    require(address(vault) != address(0), "ERC4626Router/notVaultForToken");

    uint localBalance = routingOrder.token.balanceOf(address(this));

    if (localBalance >= amount) {
      // If we have enough local balance, use that
      require(TransferLib.transferToken(routingOrder.token, msg.sender, amount), "ERC4626Router/transferFailed");
      return amount;
    } else {
      // Need to withdraw from vault
      uint toWithdraw = amount - localBalance;
      vault.withdraw(toWithdraw, msg.sender, address(this));

      // Transfer any remaining amount from local balance
      if (localBalance > 0) {
        require(TransferLib.transferToken(routingOrder.token, msg.sender, localBalance), "ERC4626Router/transferFailed");
      }
      return amount;
    }
  }
}
