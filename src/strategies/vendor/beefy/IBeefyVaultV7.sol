// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@mgv/lib/IERC20.sol";

/**
 * @title IBeefyVaultV7
 * @author Beefy (Modified by Mangrove DAO)
 * @notice This interface is inspired by BeefyVaultV7 on https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV7.sol
 */
interface IBeefyVaultV7 is IERC20 {
  /**
   * @dev the underlying token of the vault
   */
  function want() external view returns (IERC20);

  /**
   * @dev It calculates the total underlying value of {token} held by the system.
   * It takes into account the vault contract balance, the strategy contract balance
   *  and the balance deployed in other contracts as part of the strategy.
   */
  function balance() external view returns (uint);

  /**
   * @dev Custom logic in here for how much the vault allows to be borrowed.
   * We return 100% of tokens for now. Under certain conditions we might
   * want to keep some of the system funds at hand in the vault, instead
   * of putting them to work.
   */
  function available() external view returns (uint);

  /**
   * @dev Function for various UIs to display the current value of one of our yield tokens.
   * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
   */
  function getPricePerFullShare() external view returns (uint);

  /**
   * @dev A helper function to call deposit() with all the sender's funds.
   */
  function depositAll() external;

  /**
   * @dev The entrypoint of funds into the system. People deposit with this function
   * into the vault. The vault is then in charge of sending funds into the strategy.
   */
  function deposit(uint _amount) external;

  /**
   * @dev Function to send funds into the strategy and put them to work. It's primarily called
   * by the vault's deposit() function.
   */
  function earn() external;

  /**
   * @dev A helper function to call withdraw() with all the sender's funds.
   */
  function withdrawAll() external;

  /**
   * @dev Function to exit the system. The vault will withdraw the required tokens
   * from the strategy and pay up the token holder. A proportional number of IOU
   * tokens are burned in the process.
   */
  function withdraw(uint256 _shares) external;
}
