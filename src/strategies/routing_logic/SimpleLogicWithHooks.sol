// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleRoutingLogic} from "./SimpleRoutingLogic.sol";
import {AbstractRoutingLogic, IERC20} from "./abstract/AbstractRoutingLogic.sol";

/// @title SimpleLogicWithHooks
/// @author Mangrove DAO
/// @notice Adding hooks support to SimpleRoutingLogic
/// @dev this contract is abstract as if no hooks is implemented, then use {@link SimpleRoutingLogic}
abstract contract SimpleLogicWithHooks is SimpleRoutingLogic {
  /// @notice Hook called before pulling liquidity
  /// @param token the token to pull
  /// @param fundOwner the owner of the fund
  /// @param amount the amount to pull
  /// @param strict whether to pull exactly the amount or the maximum available
  function __onPullBefore__(IERC20 token, address fundOwner, uint amount, bool strict) internal virtual {}

  /// @notice Hook called after pulling liquidity
  /// @param token the token to pull
  /// @param fundOwner the owner of the fund
  /// @param amount the amount pulled
  /// @param strict whether to pull exactly the amount or the maximum available
  /// @dev this will be the last hook called in the pull logic
  /// * It is then preferrable to execute any external logic here so that if sourcing fails, the gas cost is limited
  function __onPullAfter__(IERC20 token, address fundOwner, uint amount, bool strict) internal virtual {}

  /// @notice Hook called before pushing liquidity
  /// @param token the token to push
  /// @param fundOwner the owner of the fund
  /// @param amount the amount to push
  function __onPushBefore__(IERC20 token, address fundOwner, uint amount) internal virtual {}

  /// @notice Hook called after pushing liquidity
  /// @param token the token to push
  /// @param fundOwner the owner of the fund
  /// @param amount the amount pushed
  function __onPushAfter__(IERC20 token, address fundOwner, uint amount) internal virtual {}

  /// @inheritdoc AbstractRoutingLogic
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict)
    public
    virtual
    override
    returns (uint pulled)
  {
    __onPullBefore__(token, fundOwner, amount, strict);
    pulled = super.pullLogic(token, fundOwner, amount, strict);
    __onPullAfter__(token, fundOwner, pulled, strict);
  }

  /// @inheritdoc AbstractRoutingLogic
  function pushLogic(IERC20 token, address fundOwner, uint amount) public virtual override returns (uint pushed) {
    __onPushBefore__(token, fundOwner, amount);
    pushed = super.pushLogic(token, fundOwner, amount);
    __onPushAfter__(token, fundOwner, pushed);
  }
}
