// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

/// @title VaultLogic
/// @notice Abstract contract for routing logic for a vault token
abstract contract VaultLogic is AbstractRoutingLogic {
  /// @notice Constructor
  /// @param pullGasReq_ gas requirements for `pull` logic execution regardless of the token
  /// @param pushGasReq_ gas requirements for `push` logic execution regardless of the token
  constructor(uint pullGasReq_, uint pushGasReq_) AbstractRoutingLogic(pullGasReq_, pushGasReq_) {}

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
  /// @return deposited The amount of `token` deposited
  function __deposit__(IERC20 token, uint amount, address onBehalf) internal virtual returns (uint);

  /// @notice withdraw `amount` of `token` from the vault
  /// @dev if the token is not supported, throws
  /// * If `to` option is not supported by underlying protocol, this function transfers the tokens to `to` after withdrawn
  /// @param token The ERC20 token to withdraw
  /// @param amount The amount of `token` to withdraw
  /// @param to The address to withdraw the tokens to
  /// @return withdrawn The amount of `token` withdrawn
  function __withdraw__(IERC20 token, uint amount, address to) internal virtual returns (uint);

  /// @inheritdoc AbstractRoutingLogic
  function executePullLogic(IERC20 token, uint amount, DispatcherRouter.PullStruct calldata pullData)
    external
    virtual
    override
    returns (uint)
  {
    DispatcherRouter(msg.sender).executeTransfer(token, IERC20(__vault_token__(token)), amount, pullData);

    return __withdraw__(token, amount, pullData.caller);
  }

  /// @inheritdoc AbstractRoutingLogic
  function executePushLogic(IERC20 token, uint amount, DispatcherRouter.PushStruct calldata pushData)
    external
    virtual
    override
    returns (uint)
  {
    return __deposit__(token, amount, pushData.owner);
  }
}
