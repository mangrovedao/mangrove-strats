// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity ^0.8.15;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldMode} from "@mgv/src/toy/blast/Blast.sol";

contract ERC20Rebasing is ERC20 {
  /// @notice Mapping that stores the configured yield mode for each account.
  mapping(address => YieldMode) private _yieldMode;

  /// @notice Emitted when an account configures their yield mode.
  /// @param account   Address of the account.
  /// @param yieldMode Yield mode that was configured.
  event Configure(address indexed account, YieldMode yieldMode);

  /// @param _name     Token name.
  /// @param _symbol   Token symbol.
  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

  /// @notice --- Blast Interface ---

  /// @notice Query an account's configured yield mode.
  /// @param account Address to query the configuration.
  /// @return Configured yield mode.
  function getConfiguration(address account) public view returns (YieldMode) {
    return _yieldMode[account];
  }

  /// @notice Change the yield mode of the caller and update the
  ///         balance to reflect the configuration.
  /// @param yieldMode Yield mode to configure
  /// @return Current user balance
  function configure(YieldMode yieldMode) external returns (uint) {
    emit Configure(msg.sender, yieldMode);
    _configure(msg.sender, yieldMode);

    emit Configure(msg.sender, yieldMode);

    return balanceOf(msg.sender);
  }

  /// @notice Configures a new yield mode for an account and updates
  ///         the balance storage to reflect the change.
  /// @param account      Address of the account to configure.
  /// @param newYieldMode New yield mode to configure.
  function _configure(address account, YieldMode newYieldMode) internal {
    // uint balance = balanceOf(account);

    // YieldMode prevYieldMode = getConfiguration(account);
    _yieldMode[account] = newYieldMode;
  }
}
