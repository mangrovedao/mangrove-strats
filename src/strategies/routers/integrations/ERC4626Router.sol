// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

contract ERC4626Router is AbstractRouter {
  mapping(IERC20 => ERC4626) public vaults;

  function setVaultForToken(IERC20 token, ERC4626 vault) external virtual onlyAdmin {
    vaults[token] = vault;
  }

  function __push__(IERC20 token, uint amount) internal override {
    ERC4626 vault = vaults[token];
    if (address(vault) == address(0)) {
      revert("Vault not set for token");
    }
    vault.deposit(amount, msg.sender);
  }

  function __pull__(IERC20 token, uint amount) internal override {
    ERC4626 vault = vaults[token];
    if (address(vault) == address(0)) {
      revert("Vault not set for token");
    }
    vault.withdraw(amount, msg.sender);
  }
}

contract MorphoVaultRouter is ERC4626Router {
  function setVaultForToken(IERC20 token, ERC4626 vault) external override onlyAdmin {
    if (!MORPHO_VAULT.isMorphoVault(address(vault))) {
      revert("Vault is not a Morpho vault");
    }
    vaults[token] = vault;
  }
}
