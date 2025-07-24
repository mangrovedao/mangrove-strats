// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {ICToken} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {CompoundV2Router} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {CompoundKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundKandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

/// @title Mock Interest Rate Model
/// @notice A simple mock implementation of Compound's InterestRateModel
contract MockInterestRateModel {
  /// @notice Base borrow rate per block (e.g., 2% APR ≈ 1e15 per block)
  uint public constant baseBorrowRate = 1e15;

  /// @notice Multiplier for utilization rate (e.g., 20% slope)
  uint public constant multiplier = 2e17;

  /// @notice Supply rate factor (1 - reserve factor)
  uint public constant supplyRateFactor = 9e17; // 90%

  /// @notice Calculates the current borrow interest rate per block
  /// @param cash The total amount of cash the market has
  /// @param borrows The total amount of borrows the market has outstanding
  /// @param reserves The total amount of reserves the market has
  /// @return The borrow rate per block (scaled by 1e18)
  function getBorrowRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
    if (borrows == 0) return baseBorrowRate;

    // Utilization rate = borrows / (cash + borrows - reserves)
    uint totalSupply = cash + borrows - reserves;
    if (totalSupply == 0) return baseBorrowRate;

    uint utilizationRate = (borrows * 1e18) / totalSupply;
    return baseBorrowRate + (utilizationRate * multiplier) / 1e18;
  }

  /// @notice Calculates the current supply interest rate per block
  /// @param cash The total amount of cash the market has
  /// @param borrows The total amount of borrows the market has outstanding
  /// @param reserves The total amount of reserves the market has
  /// @param reserveFactorMantissa The current reserve factor the market has
  /// @return The supply rate per block (scaled by 1e18)
  function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa)
    external
    pure
    returns (uint)
  {
    uint borrowRate = getBorrowRate(cash, borrows, reserves);

    if (borrows == 0) return 0;

    uint totalSupply = cash + borrows - reserves;
    if (totalSupply == 0) return 0;

    uint utilizationRate = (borrows * 1e18) / totalSupply;
    uint rateToPool = (borrowRate * (1e18 - reserveFactorMantissa)) / 1e18;
    return (utilizationRate * rateToPool) / 1e18;
  }
}

/// @title MockCToken
/// @notice A complete mock implementation of Compound's cToken interface for testing
/// @dev Inherits from OpenZeppelin ERC20 and implements full ICToken interface
contract MockCToken is ERC20 {
  /// @notice The underlying ERC20 token
  IERC20 public immutable underlyingToken;

  /// @notice Exchange rate stored (scaled by 1e18)
  uint public exchangeRateStored = 1e18;

  /// @notice Block number that interest was last accrued at
  uint public accrualBlockNumber;

  /// @notice Total amount of outstanding borrows of the underlying in this market
  uint public totalBorrows;

  /// @notice Total amount of reserves of the underlying held in this market
  uint public totalReserves;

  /// @notice Accumulator of the total earned interest rate since the opening of the market
  uint public borrowIndex = 1e18;

  /// @notice Fraction of interest currently set aside for reserves (scaled by 1e18)
  uint public reserveFactorMantissa = 1e17; // 10%

  /// @notice The interest rate model used to determine interest rates
  MockInterestRateModel public immutable interestRateModel;

  /// @notice Mapping of account balances in underlying tokens
  mapping(address => uint) private _underlyingBalances;

  /// @notice Total underlying tokens held by this contract
  uint public totalUnderlying;

  /// @notice Emitted when tokens are minted
  event Mint(address minter, uint mintAmount, uint mintTokens);

  /// @notice Emitted when tokens are redeemed
  event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

  /// @notice Emitted when exchange rate is updated
  event ExchangeRateUpdated(uint oldRate, uint newRate);

  /// @notice Emitted when interest is accrued
  event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

  /// @notice Constructor
  /// @param _underlying The underlying ERC20 token
  /// @param _name The name of the cToken
  /// @param _symbol The symbol of the cToken
  constructor(IERC20 _underlying, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    underlyingToken = _underlying;
    accrualBlockNumber = block.number;
    interestRateModel = new MockInterestRateModel();
  }

  /// @notice Returns the address of the underlying asset
  /// @return The address of the underlying ERC20 token
  function underlying() external view returns (address) {
    return address(underlyingToken);
  }

  /// @notice Returns the current balance of underlying tokens for an account
  /// @param account The account to check balance for
  /// @return The underlying token balance
  function balanceOfUnderlying(address account) external returns (uint) {
    _accrueInterest();
    uint cTokenBalance = balanceOf(account);
    if (cTokenBalance == 0) return 0;

    uint underlyingBalance = (cTokenBalance * exchangeRateStored) / 1e18;
    _underlyingBalances[account] = underlyingBalance;
    return underlyingBalance;
  }

  /// @notice Get underlying balance without state changes (for view-like calls)
  /// @param account The account to check balance for
  /// @return The underlying token balance
  function getUnderlyingBalance(address account) external view returns (uint) {
    uint cTokenBalance = balanceOf(account);
    if (cTokenBalance == 0) return 0;
    return (cTokenBalance * exchangeRateStored) / 1e18;
  }

  /// @notice Returns account snapshot for the given account
  /// @param account The account to get snapshot for
  /// @return error code, cToken balance, borrow balance, exchange rate
  function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {
    return (0, balanceOf(account), 0, exchangeRateStored);
  }

  /// @notice Returns the current total cash (underlying tokens held by this contract)
  /// @return The amount of underlying tokens held by this contract
  function totalCash() external view returns (uint) {
    return underlyingToken.balanceOf(address(this));
  }

  /// @notice Mints cTokens in exchange for underlying tokens
  /// @param mintAmount The amount of underlying tokens to supply
  /// @return Error code (0 for success)
  function mint(uint mintAmount) external returns (uint) {
    if (mintAmount == 0) return 1; // Error: invalid amount

    _accrueInterest();

    // Transfer underlying tokens from user
    bool success = underlyingToken.transferFrom(msg.sender, address(this), mintAmount);
    if (!success) return 2; // Error: transfer failed

    // Calculate cTokens to mint based on exchange rate
    uint cTokensToMint = (mintAmount * 1e18) / exchangeRateStored;

    // Mint cTokens to user
    _mint(msg.sender, cTokensToMint);

    // Update total underlying
    totalUnderlying += mintAmount;
    _underlyingBalances[msg.sender] += mintAmount;

    emit Mint(msg.sender, mintAmount, cTokensToMint);
    return 0; // Success
  }

  /// @notice Redeems underlying tokens in exchange for cTokens
  /// @param redeemAmount The amount of underlying tokens to redeem
  /// @return Error code (0 for success)
  function redeemUnderlying(uint redeemAmount) external returns (uint) {
    if (redeemAmount == 0) return 1; // Error: invalid amount

    _accrueInterest();

    // Calculate cTokens needed based on exchange rate
    uint cTokensNeeded = (redeemAmount * 1e18) / exchangeRateStored;

    // Check user has enough cTokens
    if (balanceOf(msg.sender) < cTokensNeeded) return 3; // Error: insufficient balance

    // Check contract has enough underlying
    if (underlyingToken.balanceOf(address(this)) < redeemAmount) return 4; // Error: insufficient cash

    return _doRedeem(msg.sender, cTokensNeeded, redeemAmount);
  }

  /// @notice Redeems cTokens in exchange for underlying tokens
  /// @param redeemTokens The amount of cTokens to redeem
  /// @return Error code (0 for success)
  function redeem(uint redeemTokens) external returns (uint) {
    if (redeemTokens == 0) return 1; // Error: invalid amount

    _accrueInterest();

    // Check user has enough cTokens
    if (balanceOf(msg.sender) < redeemTokens) return 3; // Error: insufficient balance

    // Calculate underlying amount based on exchange rate
    uint underlyingAmount = (redeemTokens * exchangeRateStored) / 1e18;

    // Check contract has enough underlying
    if (underlyingToken.balanceOf(address(this)) < underlyingAmount) return 4; // Error: insufficient cash

    return _doRedeem(msg.sender, redeemTokens, underlyingAmount);
  }

  /// @notice Internal function to handle redemption logic
  /// @param redeemer The account redeeming tokens
  /// @param redeemTokens The amount of cTokens to burn
  /// @param underlyingAmount The amount of underlying to transfer
  /// @return Error code (0 for success)
  function _doRedeem(address redeemer, uint redeemTokens, uint underlyingAmount) internal returns (uint) {
    // Burn cTokens from user
    _burn(redeemer, redeemTokens);

    // Transfer underlying tokens to user
    bool success = underlyingToken.transfer(redeemer, underlyingAmount);
    if (!success) return 2; // Error: transfer failed

    // Update total underlying
    totalUnderlying -= underlyingAmount;
    if (_underlyingBalances[redeemer] >= underlyingAmount) {
      _underlyingBalances[redeemer] -= underlyingAmount;
    } else {
      _underlyingBalances[redeemer] = 0;
    }

    emit Redeem(redeemer, underlyingAmount, redeemTokens);
    return 0; // Success
  }

  /// @notice Accrues interest to update the exchange rate
  function _accrueInterest() internal {
    uint currentBlockNumber = block.number;
    uint accrualBlockNumberPrior = accrualBlockNumber;

    // Short-circuit accumulating 0 interest
    if (accrualBlockNumberPrior == currentBlockNumber) {
      return;
    }

    uint cashPrior = underlyingToken.balanceOf(address(this));
    uint borrowsPrior = totalBorrows;
    uint reservesPrior = totalReserves;
    uint borrowIndexPrior = borrowIndex;

    // Calculate the current borrow interest rate
    uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);

    // Calculate the number of blocks elapsed since the last accrual
    uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;

    // Calculate interest accumulated
    uint simpleInterestFactor = borrowRateMantissa * blockDelta;
    uint interestAccumulated = (simpleInterestFactor * borrowsPrior) / 1e18;

    uint totalBorrowsNew = interestAccumulated + borrowsPrior;
    uint totalReservesNew = (reserveFactorMantissa * interestAccumulated) / 1e18 + reservesPrior;
    uint borrowIndexNew = (simpleInterestFactor * borrowIndexPrior) / 1e18 + borrowIndexPrior;

    // Update state
    accrualBlockNumber = currentBlockNumber;
    borrowIndex = borrowIndexNew;
    totalBorrows = totalBorrowsNew;
    totalReserves = totalReservesNew;

    // Update exchange rate: (cash + borrows - reserves) / totalSupply
    uint totalSupplyTokens = totalSupply();
    if (totalSupplyTokens > 0) {
      exchangeRateStored = ((cashPrior + totalBorrowsNew - totalReservesNew) * 1e18) / totalSupplyTokens;
    }

    emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);
  }

  /// @notice Set exchange rate for testing purposes
  /// @param newRate The new exchange rate (scaled by 1e18)
  function setExchangeRate(uint newRate) external {
    require(newRate > 0, "MockCToken: exchange rate must be positive");
    uint oldRate = exchangeRateStored;
    exchangeRateStored = newRate;
    emit ExchangeRateUpdated(oldRate, newRate);
  }

  /// @notice Simulate yield growth by increasing exchange rate
  /// @param yieldBasisPoints Yield increase in basis points (100 = 1%)
  function simulateYield(uint yieldBasisPoints) external {
    uint oldRate = exchangeRateStored;
    exchangeRateStored = (exchangeRateStored * (10000 + yieldBasisPoints)) / 10000;
    emit ExchangeRateUpdated(oldRate, exchangeRateStored);
  }

  /// @notice Simulate borrowing activity for testing
  /// @param borrowAmount Amount to simulate as borrowed
  function simulateBorrow(uint borrowAmount) external {
    _accrueInterest();
    totalBorrows += borrowAmount;
  }

  /// @notice Set reserve factor for testing
  /// @param newReserveFactor New reserve factor (scaled by 1e18)
  function setReserveFactor(uint newReserveFactor) external {
    require(newReserveFactor <= 1e18, "MockCToken: reserve factor too high");
    reserveFactorMantissa = newReserveFactor;
  }

  /// @notice Advance time by simulating block progression
  /// @param blocks Number of blocks to advance
  function advanceBlocks(uint blocks) external {
    accrualBlockNumber += blocks;
    _accrueInterest();
  }

  /// @notice Emergency function to withdraw stuck tokens (testing only)
  /// @param token The token to withdraw
  /// @param amount The amount to withdraw
  function emergencyWithdraw(IERC20 token, uint amount) external {
    token.transfer(msg.sender, amount);
  }

  /// @notice Returns the stored exchange rate
  /// @return The current exchange rate
  function exchangeRateCurrent() external returns (uint) {
    _accrueInterest();
    return exchangeRateStored;
  }
}
/// @title CompoundKandel Test Contract
/// @notice Tests for Kandel strategy using Compound V2 Router

contract CompoundKandelTest is CoreKandelTest {
  CompoundV2Router router;
  MockCToken baseCToken;
  MockCToken quoteCToken;
  CompoundKandel compoundKandel;

  receive() external payable {}

  /// @notice Set up the test environment with mock compound markets
  function __setForkEnvironment__() internal override {
    super.__setForkEnvironment__();

    // Create mock cTokens for base and quote
    baseCToken = new MockCToken(base, "Compound Base", "cBASE");
    quoteCToken = new MockCToken(quote, "Compound Quote", "cQUOTE");

    // Set tokens to behave normally for testing
    base.transferResponse(TestToken.MethodResponse.Normal);
    quote.approveResponse(TestToken.MethodResponse.Normal);
  }

  /// @notice Deploy Kandel with CompoundV2Router
  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    uint kandel_gasreq = 800_000;

    // Deploy Compound V2 Router
    router = new CompoundV2Router();

    // Set compound markets for base and quote tokens
    router.setMarket(ICToken(address(baseCToken)));
    router.setMarket(ICToken(address(quoteCToken)));

    // Create CompoundKandel with router
    compoundKandel = new CompoundKandel(
      mgv, olKey, kandel_gasreq, Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: strict})
    );

    // Bind router to kandel
    router.bind(address(compoundKandel));

    // Set admin
    compoundKandel.setAdmin(deployer);
    router.setAdmin(address(compoundKandel));

    // Give approval for kandel to pull tokens
    base.approve(address(compoundKandel), type(uint).max);
    quote.approve(address(compoundKandel), type(uint).max);

    return compoundKandel;
  }

  function test_setup() public {
    assertEq(address(compoundKandel.router()), address(router), "Router not set correctly");
    assertTrue(router.isBound(address(compoundKandel)), "Kandel not bound to router");
    assertEq(router.admin(), address(compoundKandel), "Router admin not set correctly");
  }

  function test_deposit_funds() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6; // 1000 USDC

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    uint baseCTokensBefore = baseCToken.balanceOf(address(router));
    uint quoteCTokensBefore = quoteCToken.balanceOf(address(router));

    compoundKandel.depositFunds(baseAmount, quoteAmount);

    assertEq(base.balanceOf(address(router)), 0, "Base not deposited correctly");
    assertEq(quote.balanceOf(address(router)), 0, "Quote not deposited correctly");

    assertTrue(baseCToken.balanceOf(address(router)) > baseCTokensBefore, "Base cTokens not minted correctly");
    assertTrue(quoteCToken.balanceOf(address(router)) > quoteCTokensBefore, "Quote cTokens not minted correctly");
  }

  function test_withdraw_funds() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    compoundKandel.depositFunds(baseAmount, quoteAmount);
    vm.prank(maker);
    compoundKandel.withdrawFunds(baseAmount, quoteAmount, address(this));

    assertEq(base.balanceOf(address(this)), baseAmount, "Base not withdrawn correctly");
    assertEq(quote.balanceOf(address(this)), quoteAmount, "Quote not withdrawn correctly");
  }

  function test_admin_withdraw_tokens() public {
    TestToken randomToken = new TestToken($(this), "RandomToken", "RT", 18);
    uint tokenAmount = 10 ether;
    deal($(randomToken), address(router), tokenAmount);
    uint makerBalanceBefore = randomToken.balanceOf(address(this));
    vm.prank(maker);
    router.adminWithdrawTokens(base, quote, randomToken, tokenAmount, address(this));
    uint makerBalanceAfter = randomToken.balanceOf(address(this));
    assertEq(makerBalanceAfter - makerBalanceBefore, tokenAmount);
  }

  function test_admin_withdraw_native() public {
    uint etherAmount = 10 ether;
    deal(address(router), etherAmount);
    uint makerBalanceBefore = address(this).balance;
    vm.prank(maker);
    router.adminWithdrawNative(etherAmount, address(this));
    uint makerBalanceAfter = address(this).balance;
    assertEq(makerBalanceAfter - makerBalanceBefore, etherAmount);
  }

  function test_set_market_for_token() public virtual {
    // Create new mock cToken
    MockCToken newBaseCToken = new MockCToken(base, "New Compound Base", "newCBASE");

    vm.prank(address(maker));
    router.setMarket(ICToken(address(newBaseCToken)));
    assertEq(address(router.markets(base)), address(newBaseCToken));
  }

  function test_reserve_balance() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    uint baseReservesBefore = compoundKandel.reserveBalance(Ask);
    uint quoteReservesBefore = compoundKandel.reserveBalance(Bid);

    compoundKandel.depositFunds(baseAmount, quoteAmount);

    assertEq(compoundKandel.reserveBalance(Ask) - baseReservesBefore, baseAmount, "Incorrect base reserve change");
    assertEq(compoundKandel.reserveBalance(Bid) - quoteReservesBefore, quoteAmount, "Incorrect quote reserve change");
  }

  function test_strats_with_same_admin_but_different_id_do_not_share_liquidity(uint16 baseAmount, uint16 quoteAmount)
    public
  {
    deal($(base), maker, baseAmount);
    deal($(quote), maker, quoteAmount);
    GeometricKandel kdl_ = __deployKandel__(maker, address(0), true);
    assertTrue(kdl_.FUND_OWNER() != kdl.FUND_OWNER(), "Strats should not have the same reserveId");
    vm.prank(maker);
    kdl.depositFunds(baseAmount, quoteAmount);

    assertEq(kdl_.reserveBalance(Ask), 0, "funds should not be shared");
    assertEq(kdl_.reserveBalance(Bid), 0, "funds should not be shared");
  }

  function test_yield_simulation() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    compoundKandel.depositFunds(baseAmount, quoteAmount);

    // Get initial reserves
    uint initialBaseReserve = compoundKandel.reserveBalance(Ask);
    uint initialQuoteReserve = compoundKandel.reserveBalance(Bid);

    // Simulate 5% yield on both markets
    baseCToken.simulateYield(500); // 5%
    quoteCToken.simulateYield(500); // 5%

    // Check that reserves increased due to yield
    uint newBaseReserve = compoundKandel.reserveBalance(Ask);
    uint newQuoteReserve = compoundKandel.reserveBalance(Bid);

    assertTrue(newBaseReserve > initialBaseReserve, "Base reserves should increase with yield");
    assertTrue(newQuoteReserve > initialQuoteReserve, "Quote reserves should increase with yield");
  }

  fallback() external {}

  /// @notice Test precision for compound operations
  function precisionForAssert() internal pure override returns (uint) {
    return 1; // Allow small rounding differences due to exchange rate calculations
  }

  // /// @notice Get ABI path for gas measurements
  // function getAbiPath() internal pure override returns (string memory) {
  //   return "/out/CompoundKandel.sol/CompoundKandel.json";
  // }
}
