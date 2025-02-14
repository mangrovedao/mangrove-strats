// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ERC4626Router is AbstractRouter {
  error NotVaultForToken();

  function withdraw(IERC20 token, uint amount) external onlyBound returns (uint) {
    RL.RoutingOrder memory routingOrder = RL.createOrder({fundOwner: msg.sender, token: token});
    return __pull__(routingOrder, amount, true);
  }

  mapping(IERC20 => IERC4626) public vaults;

  function setVaultForToken(IERC20 token, IERC4626 vault) external virtual onlyAdmin {
    vaults[token] = vault;
  }

  function pushAndDeposit(IERC20 token0, uint amount0, IERC20 token1, uint amount1)
    external
    onlyBound
    returns (uint pushed0, uint pushed1)
  {
    // Push will fail for amount of 0, but since this function is only called for the first maker contract in a chain
    // it needs to also flush tokens with a contract-local 0 amount.
    // token[0/1] can be address(0) if using this function for only one token
    if (address(token0) != address(0)) {
      pushed0 = __push__(RL.createOrder({fundOwner: address(this), token: token0}), amount0);
      _deposit(token0);
    }
    if (address(token1) != address(0)) {
      pushed1 = __push__(RL.createOrder({fundOwner: address(this), token: token1}), amount1);
      _deposit(token1);
    }
  }

  ///@inheritdoc AbstractRouter
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint balance) {
    balance = IERC20(routingOrder.token).balanceOf(address(this));
    IERC4626 vault = vaults[routingOrder.token];
    if (address(vault) != address(0)) {
      balance += vault.convertToAssets(vault.balanceOf(address(this)));
    }
  }

  function _deposit(IERC20 token) internal {
    IERC4626 vault = vaults[token];
    if (address(vault) == address(0)) {
      revert NotVaultForToken();
    }
    uint balance = token.balanceOf(address(this));
    if (balance > 0) {
      uint maxDeposit = vault.maxDeposit(address(this));
      uint toDeposit = maxDeposit < balance ? maxDeposit : balance;
      token.approve(address(vault), toDeposit);
      vault.deposit(toDeposit, address(this));
    }
  }

  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal override returns (uint) {
    require(
      TransferLib.transferTokenFrom(routingOrder.token, msg.sender, address(this), amount), "ERC4626Router/pushFailed"
    );
    return amount;
  }

  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict) internal override returns (uint) {
    IERC4626 vault = vaults[routingOrder.token];
    if (address(vault) == address(0)) {
      revert NotVaultForToken();
    }

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
