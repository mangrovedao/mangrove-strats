// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {IBeefyVaultV7} from "@mgv-strats/src/strategies/vendor/beefy/IBeefyVaultV7.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title BeefyCommonLogic
/// @author Mangrove DAO
/// @notice This contracts contains common logic for Beefy vaults
/// @dev This contract does not inherit `AbstractRoutingLogic`.
/// * this is because all functions of this contract will take the vault address as parameter.
/// * Usable routing logics will just call this logic with their given vault.
contract BeefyCommonLogic {
  /**
   * @notice Pulls a specific amount of tokens from the fund owner
   * @param vault The vault to pull from
   * @param to The address to pull to (usually the msg.sender but can also be this to redeem if the underlying is an LP token)
   * @param token The token to pull
   * @param fundOwner The owner of the fund
   * @param amount The amount of tokens to pull
   * @param strict Whether to enforce strict pulling
   * @return pulled The actual amount of tokens pulled
   */
  function pullLogic(IBeefyVaultV7 vault, address to, IERC20 token, address fundOwner, uint amount, bool strict)
    external
    virtual
    returns (uint pulled)
  {
    uint amount_ = strict ? amountToShares(vault, amount) : vault.balanceOf(fundOwner);
    if (amount_ == 0) {
      return 0;
    }
    // fetching overlyings from owner's account
    require(TransferLib.transferTokenFrom(vault, fundOwner, address(this), amount_), "BeefyCommonLogic/pullFailed");
    // redeem from the pool
    vault.withdraw(amount_);
    // pulled amount is the amount of token on the contract
    pulled = token.balanceOf(address(this));
    // if this is strict, we will compare the received amount with the requested amount
    if (strict) {
      require(pulled >= amount, "BeefyCommonLogic/pullFailed");
      if (pulled > amount) {
        // If we pulled more than the requested amount, we will send the difference back to the fund owner
        uint diff = pulled - amount;
        TransferLib.approveToken(token, address(vault), diff);
        vault.deposit(diff);
        // send the minted shares back to the fund owner
        require(
          TransferLib.transferToken(vault, fundOwner, vault.balanceOf(address(this))), "BeefyCommonLogic/pullFailed"
        );
        pulled = amount;
      }
    }
    // send the pulled amount to the caller
    require(TransferLib.transferToken(token, to, pulled), "BeefyCommonLogic/pullFailed");
  }

  /**
   * @notice Pushes a specific amount of tokens to the fund owner
   * @param vault The vault to push to
   * @param from The address to push from (usually the msg.sender but can also be this to depsoit if the underlying is an LP token)
   * @param token The token to push
   * @param fundOwner The owner of the fund
   * @param amount The amount of tokens to push
   * @return pushed The actual amount of tokens pushed
   */
  function pushLogic(IBeefyVaultV7 vault, address from, IERC20 token, address fundOwner, uint amount)
    external
    virtual
    returns (uint pushed)
  {
    if (from != address(this)) {
      // funds are on MakerContract, they need first to be transferred to this contract before being deposited
      require(TransferLib.transferTokenFrom(token, from, address(this), amount), "BeefyCommonLogic/pushFailed");
    }
    TransferLib.approveToken(token, address(vault), amount);
    vault.deposit(amount);
    require(TransferLib.transferToken(vault, fundOwner, vault.balanceOf(address(this))), "BeefyCommonLogic/pushFailed");
    pushed = amount;
  }

  /**
   * @notice Returns the token balance of the fund owner
   * @param vault The vault to check the balance for
   * @param fundOwner The owner of the fund
   * @return balance The balance of the token
   */
  function balanceLogic(IBeefyVaultV7 vault, address fundOwner) public view virtual returns (uint balance) {
    balance = sharesToAmount(vault, vault.balanceOf(fundOwner));
  }

  /**
   * @notice This function is used to convert shares to underlying tokens
   * @dev This uses the computation from BeefyVaultV7.withdraw()
   * The withdrawn amount for the given amount of shares should be close or equal to the amount of underlying tokens
   * There is a possibility that the amount of underlying tokens is slightly less than the withdrawn amount
   * But because of the compunding nature of beefy vaults, this should be higher.
   * It is recommended to promise a bit less than the actual amount of shares to be converted.
   * @param vault the vault to pull from
   * @param shares the amount of shares to convert
   * @return amount the amount of underlying tokens
   */
  function sharesToAmount(IBeefyVaultV7 vault, uint shares) public view returns (uint amount) {
    amount = (vault.balance() * shares) / vault.totalSupply();
  }

  /**
   * @notice This function is used to convert underlying tokens to shares
   * @param vault the vault to pull from
   * @param amount the amount of underlying tokens to convert
   * @return shares the amount of shares
   */
  function amountToShares(IBeefyVaultV7 vault, uint amount) public view returns (uint shares) {
    shares = (amount * vault.totalSupply()) / vault.balance();
    // round up shares
    shares = shares + 1;
  }
}
