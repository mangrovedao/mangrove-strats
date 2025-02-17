// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ERC4626Router is AbstractRouter {
  error NotVaultForToken();

  mapping(IERC20 => IERC4626) public vaults;
  mapping(IERC20 => uint) internal _totalShares;
  mapping(IERC20 => mapping(address => uint)) public _sharesOf;

  function withdraw(IERC20 token, uint amount) external onlyBound returns (uint) {
    RL.RoutingOrder memory routingOrder = RL.createOrder({fundOwner: msg.sender, token: token});
    return __pull__(routingOrder, amount, true);
  }

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
      pushed0 = __push__(RL.createOrder({fundOwner: msg.sender, token: token0}), amount0);
      _deposit(token0);
    }
    if (address(token1) != address(0)) {
      pushed1 = __push__(RL.createOrder({fundOwner: msg.sender, token: token1}), amount1);
      _deposit(token1);
    }
  }

  ///@inheritdoc AbstractRouter
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint balance) {
    uint sharesBalance = sharesOf(routingOrder.token, routingOrder.fundOwner);
    if (sharesBalance == 0) return 0;
    return sharesOf(routingOrder.token, routingOrder.fundOwner) * _tokenBalance(routingOrder.token)
      / _totalShares[routingOrder.token];
  }

  function _tokenBalance(IERC20 token) public view returns (uint balance) {
    balance = token.balanceOf(address(this));
    IERC4626 vault = vaults[token];
    if (address(vault) != address(0)) {
      balance += vault.convertToAssets(vault.balanceOf(address(this)));
    }
  }

  ///@notice returns the shares of this router that are attributed to a particular reserve
  ///@param token the address of the asset
  ///@param reserveId the reserve identifier
  ///@return shares the amount of shares attributed to `reserveId`.
  ///@dev `sharesOf(token,id)/totalShares(token)` represent the portion of this contract's balance of `token`s that the `reserveId` can claim
  function sharesOf(IERC20 token, address reserveId) public view returns (uint shares) {
    shares = _sharesOf[token][reserveId];
  }

  ///@notice returns the total shares one would need to possess in order to claim the entire pool of tokens
  ///@param token the address of the asset
  ///@return total the total amount of shares
  function totalShares(IERC20 token) public view returns (uint total) {
    total = _totalShares[token];
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
      TransferLib.transferTokenFrom(routingOrder.token, routingOrder.fundOwner, address(this), amount),
      "ERC4626Router/pushFailed"
    );
    _mintShares(routingOrder.token, routingOrder.fundOwner, amount);
    return amount;
  }

  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict) internal override returns (uint) {
    IERC4626 vault = vaults[routingOrder.token];
    if (address(vault) == address(0)) {
      revert NotVaultForToken();
    }

    // Burn shares before withdrawing
    _burnShares(routingOrder.token, msg.sender, amount);

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

  ///@notice mints a certain quantity of shares for a given asset and assigns them to a reserve
  ///@param token the address of the asset
  ///@param reserveId the address of the reserve who will be assigned new shares
  ///@param amount the amount of assets added to the reserve
  function _mintShares(IERC20 token, address reserveId, uint amount) internal {
    // computing how many shares should be minted for reserve
    uint sharesToMint = _sharesOfAmount(token, amount);
    _sharesOf[token][reserveId] += sharesToMint;
    _totalShares[token] += sharesToMint;
  }

  ///@notice burns a certain quantity of reserve's shares for a given asset
  ///@param token the address of the asset
  ///@param reserveId the address of the reserve who will have shares burnt
  ///@param amount the amount of assets withdrawn from reserve
  ///@dev if one is trying to burn shares from a pool that doesn't have any, the call to `_sharesOfAmount` will return `INIT_MINT`
  ///@dev and thus this contract will throw with "ERC4626Router/insufficientFunds", even if one is trying to burn 0 shares.
  function _burnShares(IERC20 token, address reserveId, uint amount) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToBurn = _sharesOfAmount(token, amount);
    uint ownerShares = _sharesOf[token][reserveId];
    require(sharesToBurn <= ownerShares, "ERC4626Router/insufficientFunds");
    // no underflow due to require above
    _sharesOf[token][reserveId] = ownerShares - sharesToBurn;
    // no underflow since _totalShares is the sum of all shares including ownerShares, and the above require.
    _totalShares[token] -= sharesToBurn;
  }

  ///@notice computes how many shares an amount of tokens represents
  ///@param token the address of the asset
  ///@param amount of tokens
  ///@return shares the shares that correspond to amount
  function _sharesOfAmount(IERC20 token, uint amount) internal view returns (uint shares) {
    uint totalShares_ = totalShares(token);
    shares = totalShares_ == 0 ? amount : totalShares_ * amount / _tokenBalance(token);
  }

  ///@notice computes how many tokens a certain number of shares represents
  ///@param token the address of the asset
  ///@param shares the number of shares to convert to tokens
  ///@return amount the amount of tokens that correspond to the shares
  function _amountOfShares(IERC20 token, uint shares) internal view returns (uint amount) {
    amount = shares * _tokenBalance(token) / totalShares(token);
  }
}
