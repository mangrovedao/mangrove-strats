// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {TransferLib2} from "@mgv-strats/src/strategies/utils/TransferLib2.sol";
import {ExponentialNoError} from "@mgv-strats/src/strategies/vendor/compound/ExponentialNoError.sol";

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

  function exchangeRateStored() external view returns (uint);

  function accrualBlockNumber() external view returns (uint);

  function totalReserves() external view returns (uint);

  function totalBorrows() external view returns (uint);

  function totalCash() external view returns (uint);

  function borrowIndex() external view returns (uint);

  function reserveFactorMantissa() external view returns (uint);

  function totalSupply() external view returns (uint);

  function interestRateModel() external view returns (InterestRateModel);
}

interface InterestRateModel {
  /**
   * @notice Calculates the current borrow interest rate per block
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @param reserves The total amount of reserves the market has
   * @return The borrow rate per block (as a percentage, and scaled by 1e18)
   */
  function getBorrowRate(uint cash, uint borrows, uint reserves) external view returns (uint);

  /**
   * @notice Calculates the current supply interest rate per block
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @param reserves The total amount of reserves the market has
   * @param reserveFactorMantissa The current reserve factor the market has
   * @return The supply rate per block (as a percentage, and scaled by 1e18)
   */
  function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa)
    external
    view
    returns (uint);
}

interface ICompoundV2StaticCallWrapper {
  function _getBalanceOfUnderlyingHelper(ICToken cToken, address account) external view returns (uint);
}

/// @title Compound V2 Router
/// @notice A router that interacts with Compound V2 markets for yield optimization
contract CompoundV2Router is AbstractRouter, ExponentialNoError {
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
    return _getBalanceOfUnderlyingHelper(cToken, account);
  }

  /// @notice Helper function that calls balanceOfUnderlying and reverts with the result
  /// @param cToken The cToken to check balance of
  /// @param account The account to check balance for
  function _getBalanceOfUnderlyingHelper(ICToken cToken, address account) internal view returns (uint) {
    Exp memory exchangeRate = Exp({mantissa: _exchangeRateCurrent(cToken)});
    uint balance = mul_ScalarTruncate(exchangeRate, cToken.balanceOf(account));
    return balance;
  }

  function _exchangeRateCurrent(ICToken cToken) internal view returns (uint) {
    uint totalSupply = cToken.totalSupply();
    if (totalSupply == 0) return 0;
    InterestCache memory cache;
    _accrueInterest(cToken, cache);
    uint totalCash = cache.cashPrior;
    uint totalBorrows = cache.totalBorrows;
    uint totalReserves = cache.totalReserves;
    uint exchangeRate = (totalCash + totalBorrows - totalReserves) * expScale / totalSupply;
    return exchangeRate;
  }

  // Maximum borrow rate that can ever be applied (.0005% / block)
  uint internal constant borrowRateMaxMantissa = 0.0005e16;

  // Maximum fraction of interest that can be set aside for reserves
  uint internal constant reserveFactorMaxMantissa = 1e18;

  struct InterestCache {
    uint accrualBlock;
    uint cashPrior;
    uint totalBorrows;
    uint totalReserves;
    uint borrowIndex;
  }

  /// @notice Reads the current state from the cToken
  /// @param cToken The cToken to read state from
  /// @return cache The populated InterestCache with current values
  function _readCTokenState(ICToken cToken) internal view virtual returns (InterestCache memory cache) {
    cache.accrualBlock = cToken.accrualBlockNumber();
    cache.cashPrior = IERC20(cToken.underlying()).balanceOf(address(cToken));
    cache.totalBorrows = cToken.totalBorrows();
    cache.totalReserves = cToken.totalReserves();
    cache.borrowIndex = cToken.borrowIndex();
  }

  /// @notice Calculates the new interest values based on elapsed blocks
  /// @param cToken The cToken to calculate interest for
  /// @param cache The current state cache
  /// @param blockDelta The number of blocks elapsed
  /// @return newTotalBorrows The new total borrows amount
  /// @return newTotalReserves The new total reserves amount
  /// @return newBorrowIndex The new borrow index
  function _calculateNewInterestValues(ICToken cToken, InterestCache memory cache, uint blockDelta)
    internal
    view
    virtual
    returns (uint newTotalBorrows, uint newTotalReserves, uint newBorrowIndex)
  {
    InterestRateModel interestRateModel = cToken.interestRateModel();

    // Calculate the current borrow interest rate
    uint borrowRateMantissa = interestRateModel.getBorrowRate(cache.cashPrior, cache.totalBorrows, cache.totalReserves);
    require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

    // Calculate simple interest factor and accumulated interest
    Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
    uint interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, cache.totalBorrows);

    // Calculate new values
    newTotalBorrows = interestAccumulated + cache.totalBorrows;
    newTotalReserves = mul_ScalarTruncateAddUInt(
      Exp({mantissa: cToken.reserveFactorMantissa()}), interestAccumulated, cache.totalReserves
    );
    newBorrowIndex = mul_ScalarTruncateAddUInt(simpleInterestFactor, cache.borrowIndex, cache.borrowIndex);
  }

  /// @notice Accrues interest for a cToken and updates the cache
  /// @param cToken The cToken to accrue interest for
  /// @param cache The cache to populate with updated values
  function _accrueInterest(ICToken cToken, InterestCache memory cache) internal view virtual {
    uint currentBlockNumber = block.number;

    // Read current state
    cache = _readCTokenState(cToken);

    // Short-circuit accumulating 0 interest
    if (cache.accrualBlock == currentBlockNumber) {
      return;
    }

    // Calculate the number of blocks elapsed since the last accrual
    uint blockDelta = currentBlockNumber - cache.accrualBlock;

    // Calculate new interest values
    (uint newTotalBorrows, uint newTotalReserves, uint newBorrowIndex) =
      _calculateNewInterestValues(cToken, cache, blockDelta);

    // Update cache with new values
    cache.accrualBlock = currentBlockNumber;
    cache.borrowIndex = newBorrowIndex;
    cache.totalBorrows = newTotalBorrows;
    cache.totalReserves = newTotalReserves;
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
