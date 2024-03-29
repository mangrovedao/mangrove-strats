// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OfferLogicTest, TestSender, IMangrove, ITesterContract} from "./abstract/OfferLogic.t.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";

import {
  AavePooledRouter,
  AbstractRouter,
  RL,
  IPoolAddressesProvider
} from "@mgv-strats/src/strategies/routers/integrations/AavePooledRouter.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "@mgv/test/lib/AllMethodIdentifiersTest.sol";
import {PoolAddressProviderMock} from "@mgv-strats/script/toy/AaveMock.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {DirectTester} from "@mgv-strats/test/lib/agents/DirectTester.sol";
import "@mgv/lib/Debug.sol";

contract AavePooledRouterTest is OfferLogicTest {
  bool internal useForkAave = true;

  DirectTester direct;

  AavePooledRouter internal pooledRouter;

  event SetAaveManager(address);
  event AaveIncident(IERC20 indexed token, address indexed maker, address indexed fundOwner, bytes32 aaveReason);

  IERC20 internal dai;
  address internal maker1;
  address internal maker2;

  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    if (useForkAave) {
      fork = new PinnedPolygonFork(39880000);
    }
    super.setUp();

    // maker contract
    maker1 = freshAddress("maker1");
    maker2 = freshAddress("maker2");

    vm.deal(maker1, 10 ether);
    vm.deal(maker2, 10 ether);

    vm.startPrank(deployer);
    pooledRouter.bind(maker1);
    pooledRouter.bind(maker2);
    vm.stopPrank();

    vm.startPrank(maker1);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
    weth.approve({spender: $(pooledRouter), amount: type(uint).max});
    usdc.approve({spender: $(pooledRouter), amount: type(uint).max});
    vm.stopPrank();

    vm.startPrank(maker2);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
    weth.approve({spender: $(pooledRouter), amount: type(uint).max});
    usdc.approve({spender: $(pooledRouter), amount: type(uint).max});
    vm.stopPrank();
  }

  // makerContract used for generic OfferLogic.t tests.
  function setupMakerContract() internal override {
    deployer = payable(address(new TestSender()));
    vm.deal(deployer, 1 ether);

    dai = useForkAave ? dai = TestToken(fork.get("DAI")) : new TestToken($(this), "Dai", "Dai", options.base.decimals);
    IPoolAddressesProvider aave = useForkAave
      ? IPoolAddressesProvider(fork.get("AaveAddressProvider"))
      : IPoolAddressesProvider(
        address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])))
      );

    vm.prank(deployer);
    AavePooledRouter router = new AavePooledRouter({addressesProvider: aave});

    vm.startPrank(deployer);
    direct = new DirectTester({
      mgv: IMangrove($(mgv)),
      routerParams: Direct.RouterParams({routerImplementation: router, fundOwner: deployer, strict: true})
    });

    makerContract = ITesterContract(address(direct));
    weth.approve(address(makerContract), type(uint).max);
    usdc.approve(address(makerContract), type(uint).max);
    vm.stopPrank();

    vm.startPrank(deployer);
    router.bind(address(makerContract));
    makerContract.activate(weth);
    makerContract.activate(usdc);
    vm.stopPrank();

    // although reserve is set to deployer the source remains makerContract since pooledRouter is always the source of funds
    // having reserve pointing to deployer allows deployer to have multiple strats with the same shares on the router
    owner = deployer;
    gasreq = 486_310;
    vm.deal(owner, 10 ether);
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE

    pooledRouter = AavePooledRouter(address(direct.router()));

    deal($(weth), address(makerContract), 1 ether);
    deal($(usdc), address(makerContract), 2000 * 10 ** 6);

    vm.startPrank(address(makerContract));
    pooledRouter.pushAndSupply(weth, 1 ether, usdc, 2000 * 10 ** 6, owner);
    vm.stopPrank();

    assertEq(pooledRouter.tokenBalanceOf(RL.createOrder(weth, owner)), 1 ether, "Incorrect weth balance");
    assertEq(pooledRouter.tokenBalanceOf(RL.createOrder(usdc, owner)), 2000 * 10 ** 6, "Incorrect usdc balance");
  }

  function test_supply_error_is_logged() public {
    TestToken pixieDust = new TestToken({admin: address(this), name: "Pixie Dust", symbol: "PXD", _decimals: uint8(18)});

    deal($(pixieDust), address(makerContract), 1 ether);
    vm.prank(address(makerContract));
    pixieDust.approve($(pooledRouter), type(uint).max);

    expectFrom($(pooledRouter));
    emit AaveIncident({
      token: pixieDust,
      maker: address(makerContract),
      fundOwner: owner,
      aaveReason: "AaveV3Lender/supplyReverted"
    });
    vm.prank(address(makerContract));
    pooledRouter.pushAndSupply(pixieDust, 1 ether, pixieDust, 0, owner);
    // although aave refused the deposit, funds should be on the router
    assertEq(pooledRouter.tokenBalanceOf(RL.createOrder(pixieDust, owner)), 1 ether, "Incorrect balance on router");
  }

  function test_initial_aave_manager_is_deployer() public {
    assertEq(pooledRouter.aaveManager(), deployer, "unexpected rewards manager");
  }

  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  function test_aave_manager_can_exit_market() public {
    // pooled router has entered weth and usdc market when first supplying
    vm.prank(deployer);
    pooledRouter.setAaveManager($(this));
    expectFrom(address(pooledRouter.POOL()));
    emit ReserveUsedAsCollateralDisabled($(weth), $(pooledRouter));
    pooledRouter.exitMarket(weth);
  }

  function test_aave_manager_can_reenter_market() public {
    // pooled router has entered weth and usdc market when first supplying
    vm.prank(deployer);
    pooledRouter.setAaveManager($(this));
    pooledRouter.exitMarket(weth);

    expectFrom(address(pooledRouter.POOL()));
    emit ReserveUsedAsCollateralEnabled($(weth), $(pooledRouter));
    pooledRouter.enterMarket(dynamic([IERC20(weth)]));
  }

  function test_deposit_on_aave_maintains_reserve_and_total_balance() public {
    deal($(usdc), maker1, 10 ** 6);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(usdc, maker1), 10 ** 6);

    uint reserveBalance = pooledRouter.tokenBalanceOf(RL.createOrder(usdc, maker1));
    uint totalBalance = pooledRouter.totalBalance(usdc);

    vm.prank(deployer);
    pooledRouter.flushBuffer(usdc, false);

    assertApproxEqAbs(
      reserveBalance, pooledRouter.tokenBalanceOf(RL.createOrder(usdc, maker1)), 1, "Incorrect reserve balance"
    );
    assertApproxEqAbs(totalBalance, pooledRouter.totalBalance(usdc), 1, "Incorrect total balance");
  }

  function test_makerContract_has_initially_zero_shares() public {
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect initial shares");
  }

  function test_push_token_increases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(RL.createOrder(dai, maker2), 2 * 10 ** 18);

    assertEq(pooledRouter.sharesOf(dai, maker2), 2 * pooledRouter.sharesOf(dai, maker1), "Incorrect shares");
  }

  function test_pull_token_decreases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(RL.createOrder(dai, maker2), 2 * 10 ** 18);

    vm.prank(maker1);
    pooledRouter.pull(RL.createOrder(dai, maker1), 1 * 10 ** 18, true);

    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_mockup_marketOrder_gas_cost() public {
    deal($(dai), maker1, 10 ** 18);

    vm.startPrank(maker1);
    uint gas = gasleft();
    pooledRouter.push(RL.createOrder(dai, maker1), 10 ** 18);
    vm.stopPrank();

    uint shallow_push_cost = gas - gasleft();

    vm.prank(deployer);
    pooledRouter.flushBuffer(dai, false);

    vm.startPrank(maker1);
    gas = gasleft();
    /// this emulates a `get` from the offer logic
    pooledRouter.pull(RL.createOrder(dai, maker1), 0.5 ether, false);
    vm.stopPrank();

    uint deep_pull_cost = gas - gasleft();

    deal($(usdc), maker1, 10 ** 6);

    vm.startPrank(maker1);
    gas = gasleft();
    pooledRouter.pushAndSupply(usdc, 10 ** 6, dai, 1 ether, maker1);
    vm.stopPrank();

    uint finalize_cost = gas - gasleft();
    console.log("deep pull: %d, finalize: %d", deep_pull_cost, finalize_cost);
    console.log("shallow push: %d", shallow_push_cost);
    console.log("Strat gasreq (%d), mockup (%d)", gasreq, deep_pull_cost + finalize_cost);
    //FIXME enable
    //assertApproxEqAbs(deep_pull_cost + finalize_cost, gasreq, 200, "Check new gas cost");
  }

  function test_push_token_increases_first_minter_shares() public {
    deal($(dai), maker1, 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 10 ** 18);
    assertEq(pooledRouter.sharesOf(dai, maker1), 10 ** pooledRouter.OFFSET(), "Incorrect first shares");
  }

  function test_pull_token_decreases_last_minter_shares_to_zero() public {
    deal($(dai), maker1, 10 ** 18);
    vm.startPrank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 10 ** 18);
    pooledRouter.pull(RL.createOrder(dai, maker1), 10 ** 18, true);
    vm.stopPrank();
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_push0() public {
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 0);
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_pull0() public {
    vm.prank(maker1);
    pooledRouter.pull(RL.createOrder(dai, maker1), 0, true);
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_donation_in_underlying_increases_user_shares(uint96 donation) public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 1 * 10 ** 18);

    deal($(dai), maker2, 4 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(RL.createOrder(dai, maker2), 4 * 10 ** 18);

    deal($(dai), maker1, donation);
    vm.prank(maker1);
    dai.transfer($(pooledRouter), donation);

    uint expectedBalance = (uint(5) * 10 ** 18 + uint(donation)) / 5;
    uint reserveBalance = pooledRouter.tokenBalanceOf(RL.createOrder(dai, maker1));
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker1");

    expectedBalance = uint(4) * (5 * 10 ** 18 + uint(donation)) / 5;
    vm.prank(maker2);
    reserveBalance = pooledRouter.tokenBalanceOf(RL.createOrder(dai, maker2));
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker2");
  }

  function test_strict_pull_with_insufficient_funds_throws_as_expected() public {
    vm.expectRevert("AavePooledRouter/insufficientFunds");
    vm.prank(maker1);
    pooledRouter.pull(RL.createOrder(dai, maker1), 1, true);
  }

  function test_non_strict_pull_with_insufficient_funds_throws_as_expected() public {
    vm.expectRevert("AavePooledRouter/insufficientFunds");
    deal($(dai), maker1, 10);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(dai, maker1), 10);
    vm.prank(maker1);
    pooledRouter.pull(RL.createOrder(dai, maker1), 11, false);
  }

  function test_strict_pull_transfers_only_amount_and_pulls_all_from_aave() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    // router has no weth on buffer and 1 weth on aave
    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, true);
    vm.stopPrank();
    assertEq(weth.balanceOf(maker1), pulled, "Incorrect maker balance");
    assertEq(weth.balanceOf($(pooledRouter)), oldAWeth - pulled, "Incorrect router balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), 0, "Incorrect aave balance");
  }

  function test_non_strict_pull_transfers_whole_balance() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, true);
    vm.stopPrank();
    assertEq(weth.balanceOf(maker1), pulled, "Incorrect balance");
  }

  function test_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    vm.stopPrank();
    // small donation
    deal($(weth), $(pooledRouter), 10);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(weth.balanceOf($(pooledRouter)), oldAWeth - pulled + 10, "Incorrect aWeth balance");
  }

  function test_non_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    vm.stopPrank();
    // donation
    deal($(weth), $(pooledRouter), 10);

    pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, false);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), 0, "Incorrect aWeth balance");
  }

  function test_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    vm.stopPrank();
    deal($(weth), $(pooledRouter), 1 ether);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth, "Incorrect aWeth balance");
  }

  function test_non_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(weth, 1 ether, weth, 0, maker1);
    vm.stopPrank();
    deal($(weth), $(pooledRouter), 1 ether);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(RL.createOrder(weth, maker1), 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth, "Incorrect aWeth balance");
  }

  function test_claim_rewards() public {
    address[] memory assets = new address[](3);
    assets[0] = address(pooledRouter.overlying(usdc));
    assets[1] = address(pooledRouter.overlying(weth));
    assets[2] = address(pooledRouter.overlying(dai));
    vm.prank(deployer);
    (address[] memory rewardsList, uint[] memory claimedAmounts) = pooledRouter.claimRewards(assets);
    for (uint i; i < rewardsList.length; i++) {
      console.logAddress(rewardsList[i]);
      console.log(claimedAmounts[i]);
    }
  }

  function empty_pool(IERC20 token, address id) internal {
    // empty usdc reserve
    uint bal = pooledRouter.tokenBalanceOf(RL.createOrder(token, id));
    if (bal > 0) {
      vm.startPrank(address(makerContract));
      pooledRouter.pull(RL.createOrder(token, owner), bal, true);
      vm.stopPrank();
    }
    assertEq(pooledRouter.tokenBalanceOf(RL.createOrder(token, id)), 0, "Non empty balance");

    assertEq(token.balanceOf($(pooledRouter)), 0, "Non empty buffer");
    assertEq(pooledRouter.overlying(token).balanceOf($(pooledRouter)), 0, "Non empty pool");
  }

  function test_overflow_shares(uint96 amount_) public {
    uint amount = uint(amount_);
    empty_pool(usdc, owner);
    empty_pool(usdc, maker1);
    empty_pool(usdc, maker2);

    deal($(usdc), maker1, amount + 1);
    // maker1 deposits 1 wei and gets 10**OFFSET shares
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(usdc, maker1), 1);
    // maker1 now deposits max uint104
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(usdc, maker1), amount);

    // computation below should not throw
    assertEq(pooledRouter.tokenBalanceOf(RL.createOrder(usdc, maker1)), amount + 1, "Incorrect balance");
  }

  function test_underflow_shares_6dec(uint96 deposit_, uint96 donation_) public {
    empty_pool(usdc, owner);
    empty_pool(usdc, maker1);
    empty_pool(usdc, maker2);

    uint deposit = uint(deposit_);
    uint donation = uint(donation_);
    vm.assume(deposit > 10 ** 5); // assume deposits at least 10-^2 tokens with 6 decimals
    vm.assume(donation < deposit * 10_000);

    deal($(usdc), maker1, donation + 1);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder(usdc, maker1), 1);

    vm.prank(maker1);
    usdc.transfer($(pooledRouter), donation);

    deal($(usdc), maker2, deposit);
    vm.prank(maker2);
    pooledRouter.push(RL.createOrder(usdc, maker2), deposit);

    assertApproxEqRel(deposit, pooledRouter.tokenBalanceOf(RL.createOrder({token: usdc, fundOwner: maker2})), 10 ** 13); // error not worth than 10^-7% of the deposit
  }

  function test_underflow_shares_18dec(uint96 deposit_, uint96 donation_) public {
    empty_pool(weth, owner);
    empty_pool(weth, maker1);
    empty_pool(weth, maker2);

    uint deposit = uint(deposit_);
    uint donation = uint(donation_);
    vm.assume(deposit > 10 ** 13); // deposits at least 10^-5 ether
    vm.assume(donation < deposit * 10_000);

    deal($(weth), maker1, donation + 1);
    vm.prank(maker1);
    pooledRouter.push(RL.createOrder({token: weth, fundOwner: maker1}), 1);

    vm.prank(maker1);
    weth.transfer($(pooledRouter), donation);

    RL.RoutingOrder memory order = RL.createOrder({token: weth, fundOwner: maker2});

    deal($(weth), maker2, deposit);
    vm.prank(maker2);
    pooledRouter.push(order, deposit);
    assertApproxEqRel(deposit, pooledRouter.tokenBalanceOf(order), 10 ** 5); // error not worth than 10^-15% of the deposit
  }

  function test_allExternalFunctions_differentCallers_correctAuth() public {
    // Arrange
    bytes[] memory selectors =
      AllMethodIdentifiersTest.getAllMethodIdentifiers(vm, "/out/AavePooledRouter.sol/AavePooledRouter.json");

    assertGt(selectors.length, 0, "Some functions should be loaded");
    RL.RoutingOrder memory routingOrder;
    routingOrder.token = weth;

    for (uint i = 0; i < selectors.length; i++) {
      // Assert that all are called - to decode the selector search in the abi file
      vm.expectCall(address(pooledRouter), selectors[i]);
    }

    address admin = freshAddress("newAdmin");
    vm.prank(deployer);
    pooledRouter.setAdmin(admin);

    address manager = freshAddress("newManager");
    vm.prank(admin);
    pooledRouter.setAaveManager(manager);

    // Act/assert - invoke all functions - if any are missing, add them.

    // No auth
    pooledRouter.ADDRESS_PROVIDER();
    pooledRouter.OFFSET();
    pooledRouter.POOL();
    pooledRouter.aaveManager();
    pooledRouter.admin();
    pooledRouter.tokenBalanceOf(routingOrder);
    pooledRouter.checkAsset(dai);
    pooledRouter.sharesOf(dai, maker1);
    pooledRouter.totalBalance(dai);
    pooledRouter.totalShares(dai);
    pooledRouter.isBound(maker1);
    pooledRouter.overlying(dai);

    routingOrder.fundOwner = maker1;

    CheckAuthArgs memory args;
    args.callee = $(pooledRouter);
    args.callers = dynamic([address($(mgv)), maker1, maker2, admin, manager, $(this), $(pooledRouter)]);
    args.revertMessage = "AccessControlled/Invalid";

    // Maker or admin
    args.allowed = dynamic([address(maker1), maker2, admin]);
    checkAuth(args, abi.encodeCall(pooledRouter.flushBuffer, (dai, true)));

    // Only admin
    args.allowed = dynamic([address(admin)]);
    address freshMaker = freshAddress("newMaker");
    checkAuth(args, abi.encodeCall(pooledRouter.setAdmin, admin));
    checkAuth(args, abi.encodeCall(pooledRouter.bind, freshMaker));
    checkAuth(args, abi.encodeWithSignature("unbind(address)", freshMaker));

    // Only Makers
    deal($(dai), maker1, 1 * 10 ** 18);
    deal($(dai), maker2, 1 * 10 ** 18);
    args.allowed = dynamic([address(maker1), maker2]);
    checkAuth(args, abi.encodeCall(pooledRouter.push, (RL.createOrder(dai, maker1), 1000)));
    checkAuth(args, abi.encodeCall(pooledRouter.pull, (RL.createOrder(dai, maker1), 100, true)));

    RL.RoutingOrder[] memory routingOrders = new RL.RoutingOrder[](0);
    checkAuth(args, abi.encodeCall(pooledRouter.flush, routingOrders));

    checkAuth(args, abi.encodeCall(pooledRouter.pushAndSupply, (dai, 0, dai, 0, owner)));
    checkAuth(args, abi.encodeCall(pooledRouter.withdraw, (dai, maker1, 100)));

    checkAuth(args, abi.encodeWithSignature("unbind()"));

    // Only manager
    args.allowed = dynamic([address(manager)]);
    checkAuth(args, abi.encodeCall(pooledRouter.enterMarket, new IERC20[](0)));
    checkAuth(args, abi.encodeCall(pooledRouter.claimRewards, dynamic([address(pooledRouter.overlying(dai))])));
    checkAuth(args, abi.encodeCall(pooledRouter.exitMarket, weth));

    // Both manager and admin
    args.allowed = dynamic([address(manager), admin]);
    checkAuth(args, abi.encodeCall(pooledRouter.setAaveManager, manager));
  }
}
