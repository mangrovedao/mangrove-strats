// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.19;

import {MonoRouter} from "./MonoRouter.sol";
import {AbstractRouter} from "./AbstractRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {ApprovalInfo} from "@mgv-strats/src/strategies/utils/ApprovalTransferLib.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title `SimpleVaultRouter` is a router contract for Simple Vaults.
abstract contract SimpleVaultRouter is MonoRouter {
  /// @notice contract's constructor
  /// @param routerGasreq_ The gas requirement for the router
  constructor(uint routerGasreq_) MonoRouter(routerGasreq_) {}

  /// @notice Gets the ERC20 token to represent the vault shares
  /// @dev if the token is not supported, returns address(0)
  /// @param token The ERC20 token to get the vault token for
  /// @return vaultToken The ERC20 token to represent the vault shares
  function __vault_token__(IERC20 token) internal view virtual returns (address);

  /// @notice Gets the ERC20 token to represent the vault shares
  /// @dev if the token is not supported, returns address(0)
  /// @param token The ERC20 token to get the vault token for
  /// @return vaultToken The ERC20 token to represent the vault shares
  function vaultToken(IERC20 token) external view returns (address) {
    return __vault_token__(token);
  }

  /// @notice deposit `amount` of `token` into the vault to `onBehalf`
  /// @dev if the token is not supported, throws
  /// * If `onBehalf` option is not supported by underlying protocol, this function transfers the tokens to `onBehalf` after vault shares are minted
  /// @param token The ERC20 token to deposit
  /// @param amount The amount of `token` to deposit
  /// @param onBehalf The address to deposit the tokens to
  function __deposit__(IERC20 token, uint amount, address onBehalf) internal virtual;

  /// @notice withdraw `amount` of `token` from the vault
  /// @dev if the token is not supported, throws
  /// * If `to` option is not supported by underlying protocol, this function transfers the tokens to `to` after withdrawn
  /// @param token The ERC20 token to withdraw
  /// @param amount The amount of `token` to withdraw
  /// @param to The address to withdraw the tokens to
  /// @return withdrawn The amount of `token` withdrawn
  function __withdraw__(IERC20 token, uint amount, address to) internal virtual returns (uint);

  /// @inheritdoc AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool, ApprovalInfo calldata)
    internal
    virtual
    override
    returns (uint pulled)
  {
    address vault_token = __vault_token__(token);
    require(vault_token != address(0), "SimpleVaultRouter/InvalidToken");

    require(
      TransferLib.transferTokenFrom(IERC20(vault_token), reserveId, address(this), amount),
      "SimpleVaultRouter/PullFailed"
    );
    return __withdraw__(token, amount, msg.sender);
  }

  /// @inheritdoc AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint pushed) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "SimpleVaultRouter/PushFailed");
    __deposit__(token, amount, reserveId);
    return amount;
  }

  /// @inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId, address) internal view virtual override {
    address vault_token = __vault_token__(token);
    require(vault_token != address(0), "SimpleVaultRouter/InvalidToken");
    require(IERC20(vault_token).allowance(reserveId, address(this)) > 0, "SimpleVaultRouter/NotApproved");
  }
}
