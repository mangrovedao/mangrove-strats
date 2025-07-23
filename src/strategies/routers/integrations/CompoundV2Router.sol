// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {TransferLib2} from "@mgv-strats/src/strategies/utils/TransferLib2.sol";

/// @title ICToken interface for Compound V2
/// @notice Interface for interacting with Compound V2 cTokens
interface ICToken is IERC20 {
  /// @notice Returns the address of the underlying asset
  /// @return The address of the underlying ERC20 token
  function underlying() external view returns (address);

  /// @notice Returns the current balance of underlying tokens for an account
  /// @param account The account to check balance for
  /// @return The underlying token balance
  function balanceOfUnderlying(address account) external returns (uint);

  /// @notice Mints cTokens in exchange for underlying tokens
  /// @param mintAmount The amount of underlying tokens to supply
  /// @return Error code (0 for success)
  function mint(uint mintAmount) external returns (uint);

  /// @notice Redeems underlying tokens in exchange for cTokens
  /// @param redeemAmount The amount of underlying tokens to redeem
  /// @return Error code (0 for success)
  function redeemUnderlying(uint redeemAmount) external returns (uint);

  /// @notice Redeems cTokens in exchange for underlying tokens
  /// @param redeemTokens The amount of cTokens to redeem
  /// @return Error code (0 for success)
  function redeem(uint redeemTokens) external returns (uint);

  function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
}

interface ICompoundV2StaticCallWrapper {
  function _getBalanceOfUnderlyingHelper(ICToken cToken, address account) external view returns (uint);
}

/// @title Compound V2 Router
/// @notice A router that interacts with Compound V2 markets for yield optimization
contract CompoundV2Router is AbstractRouter {
  /// @notice Emitted when the admin withdraws tokens
  /// @param token The token being withdrawn
  /// @param amount The amount of tokens being withdrawn
  /// @param recipient The recipient of the tokens
  event AdminTokenWithdrawal(IERC20 token, uint amount, address recipient);

  /// @notice Emitted when the admin withdraws native tokens
  /// @param amount The amount of native tokens being withdrawn
  /// @param recipient The recipient of the native tokens
  event AdminNativeWithdrawal(uint amount, address recipient);

  /// @notice Emitted when a market is set for a token
  /// @param underlying The underlying token for which the market is set
  /// @param oldMarket The previous cToken market for the underlying token
  /// @param newMarket The new cToken market for the underlying token
  event MarketSet(IERC20 indexed underlying, ICToken indexed oldMarket, ICToken indexed newMarket);

  /// @notice Custom error to return balance data when reverting
  /// @param balance The balance amount to return
  error BalanceResult(uint balance);

  /// @notice Mapping of underlying tokens to their corresponding cToken markets
  mapping(IERC20 => ICToken) public markets;

  /// @notice Withdraws tokens from the router
  /// @param token The token to withdraw
  /// @param amount The amount of tokens to withdraw
  /// @return The amount of tokens withdrawn
  function withdraw(IERC20 token, uint amount) external onlyBound returns (uint) {
    RL.RoutingOrder memory routingOrder = RL.createOrder({fundOwner: msg.sender, token: token});
    return __pull__(routingOrder, amount, true);
  }

  /// @notice Pushes tokens to the router and deposits them into Compound markets
  /// @param token0 The first token to push and deposit
  /// @param amount0 The amount of the first token to push and deposit
  /// @param token1 The second token to push and deposit
  /// @param amount1 The amount of the second token to push and deposit
  /// @return pushed0 The amount of the first token pushed and deposited
  /// @return pushed1 The amount of the second token pushed and deposited
  function pushAndDeposit(IERC20 token0, uint amount0, IERC20 token1, uint amount1)
    external
    onlyBound
    returns (uint pushed0, uint pushed1)
  {
    if (address(token0) != address(0)) {
      pushed0 = __push__(RL.createOrder({fundOwner: msg.sender, token: token0}), amount0);
      _deposit(token0);
    }
    if (address(token1) != address(0)) {
      pushed1 = __push__(RL.createOrder({fundOwner: msg.sender, token: token1}), amount1);
      _deposit(token1);
    }
  }

  /// @notice Allows the admin to withdraw tokens
  /// @param base The base token of the trading pair
  /// @param quote The quote token of the trading pair
  /// @param token The token to withdraw
  /// @param amount The amount of tokens to withdraw
  /// @param recipient The recipient of the tokens
  /// @dev Prevents withdrawal of underlying tokens or cTokens used in active markets
  function adminWithdrawTokens(IERC20 base, IERC20 quote, IERC20 token, uint amount, address recipient)
    external
    onlyAdmin
  {
    require(token != base && token != quote, "CompoundV2Router/InvalidUnderlyingToken");
    require(
      address(token) != address(markets[base]) && address(token) != address(markets[quote]),
      "CompoundV2Router/InvalidCToken"
    );

    require(TransferLib.transferToken(token, recipient, amount), "CompoundV2Router/adminWithdrawFailed");
    emit AdminTokenWithdrawal(token, amount, recipient);
  }

  /// @notice Allows the admin to withdraw native tokens
  /// @param amount The amount of native tokens to withdraw
  /// @param recipient The recipient of the native tokens
  function adminWithdrawNative(uint amount, address recipient) public onlyAdmin {
    (bool s,) = recipient.call{value: amount}("");
    require(s, "CompoundV2Router/adminWithdrawNativeFailed");
    emit AdminNativeWithdrawal(amount, recipient);
  }

  /// @notice Sets the Compound market for a specific underlying token
  /// @param cToken The cToken market to set for the underlying token
  /// @dev Automatically withdraws from old market and deposits into new market
  function setMarket(ICToken cToken) public onlyAdmin {
    address underlyingAddr = cToken.underlying();
    require(underlyingAddr != address(0), "CompoundV2Router/zeroToken");
    IERC20 underlying = IERC20(underlyingAddr);
    ICToken oldMarket = markets[underlying];
    if (address(oldMarket) != address(0) && address(oldMarket) != address(cToken)) {
      _withdrawAll(oldMarket);
    }
    markets[underlying] = cToken;
    emit MarketSet(underlying, oldMarket, cToken);
    _deposit(underlying);
  }

  /// @notice Withdraws all cTokens from a market and redeems them for underlying tokens
  /// @param market The cToken market to withdraw from
  function _withdrawAll(ICToken market) internal {
    uint cTokenBalance = market.balanceOf(address(this));
    if (cTokenBalance > 0) {
      uint redeemResult = market.redeem(cTokenBalance);
      require(redeemResult == 0, "CompoundV2Router/redeemOldMarketFailed");
    }
  }

  /// @notice Gets the balance of a token, including both local balance and assets in Compound markets
  /// @param routingOrder The routing order
  /// @return balance The balance of the token
  /// @dev Returns the sum of direct token balance and underlying balance in Compound markets
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint balance) {
    uint localBalance = routingOrder.token.balanceOf(address(this));

    ICToken cToken = markets[routingOrder.token];

    if (address(cToken) == address(0)) {
      return localBalance;
    }
    // Get compound balance using call-and-revert pattern
    uint compoundBalance = _getBalanceOfUnderlyingView(cToken, address(this));

    return localBalance + compoundBalance;
  }

  /// @notice Gets the underlying balance in a view-like manner using call-and-revert pattern
  /// @param cToken The cToken to check balance of
  /// @param account The account to check balance for
  /// @return The underlying balance
  function _getBalanceOfUnderlyingView(ICToken cToken, address account) internal view returns (uint) {
    // TODO: replace with get accoun snapshot and computation of balance of underlying.
    try ICompoundV2StaticCallWrapper(address(this))._getBalanceOfUnderlyingHelper(cToken, account) {
      // This should never succeed as the helper always reverts
      revert("Unexpected success");
    } catch (bytes memory reason) {
      // Check if it's our custom BalanceResult error
      if (reason.length >= 4) {
        bytes4 selector;
        assembly {
          selector := mload(add(reason, 0x20))
        }
        if (selector == BalanceResult.selector) {
          // Decode the balance from the error data
          // Skip the first 4 bytes (selector) and decode the rest
          bytes memory data;
          assembly {
            let dataLength := sub(mload(reason), 4)
            data := mload(0x40)
            mstore(0x40, add(data, and(add(dataLength, 0x1f), not(0x1f))))
            mstore(data, dataLength)
            let src := add(reason, 0x24) // Skip length (32 bytes) + selector (4 bytes)
            let dst := add(data, 0x20) // Skip length field
            for { let i := 0 } lt(i, dataLength) { i := add(i, 0x20) } { mstore(add(dst, i), mload(add(src, i))) }
          }
          return abi.decode(data, (uint));
        }
      }
      // If it's not our custom error, re-throw the original error
      assembly {
        revert(add(reason, 0x20), mload(reason))
      }
    }
  }

  /// @notice Helper function that calls balanceOfUnderlying and reverts with the result
  /// @param cToken The cToken to check balance of
  /// @param account The account to check balance for
  function _getBalanceOfUnderlyingHelper(ICToken cToken, address account) external {
    uint balance = cToken.balanceOfUnderlying(account);
    revert BalanceResult(balance);
  }

  /// @notice Deposits tokens into the corresponding Compound market
  /// @param token The token to deposit
  function _deposit(IERC20 token) internal {
    ICToken cToken = markets[token];
    if (address(cToken) != address(0)) {
      uint balance = token.balanceOf(address(this));
      if (balance > 0) {
        require(TransferLib2.forceApproveToken(token, address(cToken), balance), "CompoundV2Router/depositFailed");
        uint mintResult = cToken.mint(balance);
        require(mintResult == 0, "CompoundV2Router/mintFailed");
      }
    }
  }

  /// @notice Pushes tokens to the router
  /// @param routingOrder The routing order
  /// @param amount The amount of tokens to push
  /// @return pushedAmount The amount of tokens pushed
  /// @dev This function does NOT support fee-on-transfer tokens
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal override returns (uint pushedAmount) {
    require(
      TransferLib.transferTokenFrom(routingOrder.token, routingOrder.fundOwner, address(this), amount),
      "CompoundV2Router/pushFailed"
    );
    return amount;
  }

  /// @notice Pulls tokens from the router, redeeming from Compound markets if necessary
  /// @param routingOrder The routing order
  /// @param amount The amount of tokens to pull
  /// @param strict Whether to pull strictly (unused in this implementation)
  /// @return pulledAmount The amount of tokens pulled
  /// @dev Prioritizes local balance before redeeming from Compound markets
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict)
    internal
    override
    returns (uint pulledAmount)
  {
    uint localBalance = routingOrder.token.balanceOf(address(this));

    if (localBalance >= amount) {
      require(TransferLib.transferToken(routingOrder.token, msg.sender, amount), "CompoundV2Router/transferFailed");
      return amount;
    }

    ICToken cToken = markets[routingOrder.token];

    if (address(cToken) == address(0)) revert("CompoundV2Router/insufficientFunds");

    if (amount == type(uint).max) {
      _withdrawAll(cToken);
      localBalance = routingOrder.token.balanceOf(address(this));
      require(
        TransferLib.transferToken(routingOrder.token, msg.sender, localBalance), "CompoundV2Router/transferFailed"
      );
      return localBalance;
    }

    uint toWithdraw = amount - localBalance;
    uint redeemResult = cToken.redeemUnderlying(toWithdraw);
    require(redeemResult == 0, "CompoundV2Router/redeemFailed");
    require(TransferLib.transferToken(routingOrder.token, msg.sender, toWithdraw), "CompoundV2Router/transferFailed");
    return amount;
  }
}
