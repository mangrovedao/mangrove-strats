// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {MonoRouter} from "./MonoRouter.sol";
import {AbstractRouter} from "./AbstractRouter.sol";
import {IERC20} from "mgv_lib/IERC20.sol";
import {ApprovalInfo} from "mgv_strat_src/strategies/utils/ApprovalTransferLib.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

/// @title `SimpleVaultRouter` is a router contract for Simple Vaults.
abstract contract SimpleVaultRouter is MonoRouter {
  /// @notice contract's constructor
  /// @param routerGasreq_ The gas requirement for the router
  constructor(uint routerGasreq_) MonoRouter(routerGasreq_) {}

  /// @notice Gets the ERC20 token to represent the vault shares
  /// @dev if the token is not supported, returns address(0)
  /// @param token The ERC20 token to get the vault token for
  /// @return vaultToken The ERC20 token to represent the vault shares
  function __vault_token__(IERC20 token) internal view virtual returns (IERC20);

  /// @notice deposit `amount` of `token` into the vault to `onBehalf`
  /// @dev if the token is not supported, throws
  /// * If `onBehalf` option is not supported by underlying protocol, transfers the tokens to `onBehalf` after vault shares are minted
  /// @param token The ERC20 token to deposit
  /// @param amount The amount of `token` to deposit
  /// @param onBehalf The address to deposit the tokens to
  function __deposit__(IERC20 token, uint amount, address onBehalf) internal virtual;

  /// @notice withdraw `amount` of `token` from the vault
  /// @dev if the token is not supported, throws
  /// @param token The ERC20 token to withdraw
  /// @param amount The amount of `token` to withdraw
  /// @return withdrawn The amount of `token` withdrawn
  function __withdraw__(IERC20 token, uint amount) internal virtual returns (uint);

  /// @inheritdoc AbstractRouter
  function __pull__(IERC20 token, address reserveId, uint amount, bool, ApprovalInfo calldata)
    internal
    virtual
    override
    returns (uint pulled)
  {
    IERC20 vaultToken = __vault_token__(token);
    require(vaultToken != IERC20(address(0)), "SimpleVaultRouter/InvalidToken");

    require(TransferLib.transferTokenFrom(vaultToken, reserveId, address(this), amount), "SimpleVaultRouter/PullFailed");
    return __withdraw__(token, amount);
  }

  /// @inheritdoc AbstractRouter
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint pushed) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "SimpleVaultRouter/PushFailed");
    __deposit__(token, amount, reserveId);
    return amount;
  }

  /// @inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId, address) internal view virtual override {
    IERC20 vaultToken = __vault_token__(token);
    require(vaultToken != IERC20(address(0)), "SimpleVaultRouter/InvalidToken");
    require(vaultToken.allowance(reserveId, address(this)) > 0, "SimpleVaultRouter/NotApproved");
  }
}
