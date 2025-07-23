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

/// @title MockCToken
/// @notice A mock implementation of Compound's cToken interface for testing
/// @dev Inherits from OpenZeppelin ERC20 and implements ICToken interface
contract MockCToken is
  ERC20 // ICToken
{
  /// @notice The underlying ERC20 token
  IERC20 public immutable underlyingToken;

  /// @notice Exchange rate from underlying to cToken (scaled by 1e18)
  /// @dev Start with 1:1 ratio, can be modified for testing yield scenarios
  uint public exchangeRate = 1e18;

  /// @notice Mapping of account balances in underlying tokens
  /// @dev Used to track the underlying balance without state-changing calls
  mapping(address => uint) private _underlyingBalances;

  /// @notice Total underlying tokens held by this contract
  uint public totalUnderlying;

  /// @notice Emitted when tokens are minted
  event Mint(address minter, uint mintAmount, uint mintTokens);

  /// @notice Emitted when tokens are redeemed
  event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

  /// @notice Emitted when exchange rate is updated
  event ExchangeRateUpdated(uint oldRate, uint newRate);

  /// @notice Constructor
  /// @param _underlying The underlying ERC20 token
  /// @param _name The name of the cToken
  /// @param _symbol The symbol of the cToken
  constructor(IERC20 _underlying, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    underlyingToken = _underlying;
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
    // Convert cToken balance to underlying using current exchange rate
    uint cTokenBalance = balanceOf(account);
    if (cTokenBalance == 0) return 0;

    uint underlyingBalance = (cTokenBalance * exchangeRate) / 1e18;
    _underlyingBalances[account] = underlyingBalance;
    return underlyingBalance;
  }

  /// @notice Get underlying balance without state changes (for view-like calls)
  /// @param account The account to check balance for
  /// @return The underlying token balance
  function getUnderlyingBalance(address account) external view returns (uint) {
    uint cTokenBalance = balanceOf(account);
    if (cTokenBalance == 0) return 0;
    return (cTokenBalance * exchangeRate) / 1e18;
  }

  /// @notice Mints cTokens in exchange for underlying tokens
  /// @param mintAmount The amount of underlying tokens to supply
  /// @return Error code (0 for success)
  function mint(uint mintAmount) external returns (uint) {
    if (mintAmount == 0) return 1; // Error: invalid amount

    // Transfer underlying tokens from user
    bool success = underlyingToken.transferFrom(msg.sender, address(this), mintAmount);
    if (!success) return 2; // Error: transfer failed

    // Calculate cTokens to mint based on exchange rate
    uint cTokensToMint = (mintAmount * 1e18) / exchangeRate;

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

    // Calculate cTokens needed based on exchange rate
    uint cTokensNeeded = (redeemAmount * 1e18) / exchangeRate;

    // Check user has enough cTokens
    if (balanceOf(msg.sender) < cTokensNeeded) return 3; // Error: insufficient balance

    // Check contract has enough underlying
    if (underlyingToken.balanceOf(address(this)) < redeemAmount) return 4; // Error: insufficient cash

    // Burn cTokens from user
    _burn(msg.sender, cTokensNeeded);

    // Transfer underlying tokens to user
    bool success = underlyingToken.transfer(msg.sender, redeemAmount);
    if (!success) return 2; // Error: transfer failed

    // Update total underlying
    totalUnderlying -= redeemAmount;
    if (_underlyingBalances[msg.sender] >= redeemAmount) {
      _underlyingBalances[msg.sender] -= redeemAmount;
    } else {
      _underlyingBalances[msg.sender] = 0;
    }

    emit Redeem(msg.sender, redeemAmount, cTokensNeeded);
    return 0; // Success
  }

  /// @notice Redeems cTokens in exchange for underlying tokens
  /// @param redeemTokens The amount of cTokens to redeem
  /// @return Error code (0 for success)
  function redeem(uint redeemTokens) external returns (uint) {
    if (redeemTokens == 0) return 1; // Error: invalid amount

    // Check user has enough cTokens
    if (balanceOf(msg.sender) < redeemTokens) return 3; // Error: insufficient balance

    // Calculate underlying amount based on exchange rate
    uint underlyingAmount = (redeemTokens * exchangeRate) / 1e18;

    // Check contract has enough underlying
    if (underlyingToken.balanceOf(address(this)) < underlyingAmount) return 4; // Error: insufficient cash

    // Burn cTokens from user
    _burn(msg.sender, redeemTokens);

    // Transfer underlying tokens to user
    bool success = underlyingToken.transfer(msg.sender, underlyingAmount);
    if (!success) return 2; // Error: transfer failed

    // Update total underlying
    totalUnderlying -= underlyingAmount;
    if (_underlyingBalances[msg.sender] >= underlyingAmount) {
      _underlyingBalances[msg.sender] -= underlyingAmount;
    } else {
      _underlyingBalances[msg.sender] = 0;
    }

    emit Redeem(msg.sender, underlyingAmount, redeemTokens);
    return 0; // Success
  }

  /// @notice Set exchange rate for testing purposes
  /// @param newRate The new exchange rate (scaled by 1e18)
  function setExchangeRate(uint newRate) external {
    require(newRate > 0, "MockCToken: exchange rate must be positive");
    uint oldRate = exchangeRate;
    exchangeRate = newRate;
    emit ExchangeRateUpdated(oldRate, newRate);
  }

  /// @notice Simulate yield growth by increasing exchange rate
  /// @param yieldBasisPoints Yield increase in basis points (100 = 1%)
  function simulateYield(uint yieldBasisPoints) external {
    uint oldRate = exchangeRate;
    exchangeRate = (exchangeRate * (10000 + yieldBasisPoints)) / 10000;
    emit ExchangeRateUpdated(oldRate, exchangeRate);
  }

  /// @notice Emergency function to withdraw stuck tokens (testing only)
  /// @param token The token to withdraw
  /// @param amount The amount to withdraw
  function emergencyWithdraw(IERC20 token, uint amount) external {
    token.transfer(msg.sender, amount);
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
