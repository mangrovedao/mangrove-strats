pragma solidity ^0.8.20;

import {IERC20} from "@mgv/src/core/MgvLib.sol";

pragma solidity ^0.8.20;

import {IERC20} from "@mgv/src/core/MgvLib.sol";

/// @title Routing logic
abstract contract AbstractRoutingLogic {
  /**
   * @notice Pulls a specific amount of tokens from the fund owner
   * @param token The token to pull
   * @param fundOwner The owner of the fund
   * @param amount The amount of tokens to pull
   * @param strict Whether to enforce strict pulling
   * @return pulled The actual amount of tokens pulled
   */
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict) external virtual returns (uint pulled);

  /**
   * @notice Pushes a specific amount of tokens to the fund owner
   * @param token The token to push
   * @param fundOwner The owner of the fund
   * @param amount The amount of tokens to push
   * @return pushed The actual amount of tokens pushed
   */
  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual returns (uint pushed);

  /**
   * @notice Returns the token balance of the fund owner
   * @param token The token to check the balance for
   * @param fundOwner The owner of the fund
   * @return balance The balance of the token
   */
  function balanceLogic(IERC20 token, address fundOwner) external view virtual returns (uint balance);
}
