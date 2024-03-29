// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  MangroveOrder as MgvOrder,
  SmartRouter,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IOrderLogic} from "@mgv-strats/src/strategies/interfaces/IOrderLogic.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/integrations/AaveMemoizer.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/aave/v3/contracts/interfaces/IPool.sol";
import {RenegingForwarder} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";

import {TakerOrderType} from "@mgv-strats/src/strategies/TakerOrderLib.sol";

library TickNegator {
  function negate(Tick tick) internal pure returns (Tick) {
    return Tick.wrap(-Tick.unwrap(tick));
  }
}

contract MgvOrder_Test is StratTest {
  using TickNegator for Tick;

  uint constant GASREQ = 200_000; // see MangroveOrderGasreqBaseTest
  uint constant AAVE_GASREQ = 1_000_000; // see AaveGasreqBaseTest
  uint constant MID_PRICE = 2000e18;
  // to check ERC20 logging

  event MangroveOrderStart(
    bytes32 indexed olKeyHash,
    address indexed taker,
    Tick tick,
    TakerOrderType orderType,
    uint fillVolume,
    bool fillWants,
    uint offerId,
    AbstractRoutingLogic takerGivesLogic,
    AbstractRoutingLogic takerWantsLogic
  );

  event MangroveOrderComplete();

  MgvOrder internal mgo;
  TestMaker internal ask_maker;
  TestMaker internal bid_maker;

  TestTaker internal sell_taker;
  PinnedPolygonFork internal fork;

  IOrderLogic.TakerOrderResult internal cold_buyResult;
  IOrderLogic.TakerOrderResult internal cold_sellResult;

  SimpleAaveLogic internal aaveLogic;

  receive() external payable {}

  function tickFromPrice_e18(uint priceE18) internal pure returns (Tick tick) {
    (uint mantissa, uint exp) = TickLib.ratioFromVolumes(priceE18, 1e18);
    tick = TickLib.tickFromRatio(mantissa, int(exp));
  }

  function makerWants(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return
      order.fillWants ? order.fillVolume : Tick.wrap(-Tick.unwrap(order.tick)).inboundFromOutboundUp(order.fillVolume);
  }

  function makerGives(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return
      order.fillWants ? Tick.wrap(-Tick.unwrap(order.tick)).outboundFromInboundUp(order.fillVolume) : order.fillVolume;
  }

  function takerWants(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return order.fillWants ? order.fillVolume : order.tick.outboundFromInboundUp(order.fillVolume);
  }

  function takerGives(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return order.fillWants ? order.tick.inboundFromOutboundUp(order.fillVolume) : order.fillVolume;
  }

  function setUp() public override {
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH.e"));
    quote = TestToken(fork.get("DAI.e"));
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();
    setupMarket(olKey);

    RouterProxyFactory factory = new RouterProxyFactory();

    // this contract is admin of MgvOrder and its router
    mgo = new MgvOrder(IMangrove(payable(mgv)), factory, $(this));
    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)

    aaveLogic = new SimpleAaveLogic(
      IPoolAddressesProvider(fork.get("AaveAddressProvider")),
      2 // variable rate
    );

    // `this` contract will act as `MgvOrder` user
    deal($(base), $(this), 10 ether);
    deal($(quote), $(this), 10_000 ether);

    // activating MangroveOrder for quote and base
    mgo.activate(base);
    mgo.activate(quote);

    // `sell_taker` will take resting bid
    sell_taker = setupTaker(olKey, "sell-taker");
    deal($(base), $(sell_taker), 10 ether);

    // if seller wants to sell directly on mangrove
    vm.prank($(sell_taker));
    TransferLib.approveToken(base, $(mgv), 10 ether);
    // if seller wants to sell via mgo
    vm.prank($(sell_taker));
    TransferLib.approveToken(quote, $(mgv), 10 ether);

    // populating order book with offers
    ask_maker = setupMaker(olKey, "ask-maker");
    vm.deal($(ask_maker), 10 ether);

    bid_maker = setupMaker(lo, "bid-maker");
    vm.deal($(bid_maker), 10 ether);

    deal($(base), $(ask_maker), 10 ether);
    deal($(quote), $(bid_maker), 10000 ether);

    // pre populating book with cold maker offers.
    ask_maker.approveMgv(base, 10 ether);
    uint volume = 1 ether;
    ask_maker.newOfferByTickWithFunding(olKey, tickFromPrice_e18(MID_PRICE), volume, 50_000, 0, 0.1 ether);
    ask_maker.newOfferByTickWithFunding(olKey, tickFromPrice_e18(MID_PRICE + 1e18), volume, 50_000, 0, 0.1 ether);
    ask_maker.newOfferByTickWithFunding(olKey, tickFromPrice_e18(MID_PRICE + 2e18), volume, 50_000, 0, 0.1 ether);

    bid_maker.approveMgv(quote, 10000 ether);
    bid_maker.newOfferByTickWithFunding(
      lo, tickFromPrice_e18(MID_PRICE - 10e18).negate(), 2000e18, 50_000, 0, 0.1 ether
    );
    bid_maker.newOfferByTickWithFunding(
      lo, tickFromPrice_e18(MID_PRICE - 11e18).negate(), 2000e18, 50_000, 0, 0.1 ether
    );
    bid_maker.newOfferByTickWithFunding(
      lo, tickFromPrice_e18(MID_PRICE - 12e18).negate(), 2000e18, 50_000, 0, 0.1 ether
    );

    IOrderLogic.TakerOrder memory buyOrder;
    IOrderLogic.TakerOrder memory sellOrder;
    // depositing a cold MangroveOrder offer.
    buyOrder = createBuyOrderEvenLowerPriceAndLowerVolume();
    buyOrder.orderType = TakerOrderType.GTC;
    buyOrder.expiryDate = block.timestamp + 1;

    sellOrder = createSellOrderEvenLowerPriceAndLowerVolume();
    sellOrder.orderType = TakerOrderType.GTC;
    sellOrder.expiryDate = block.timestamp + 1;

    // test runner posts limit orders
    // one cannot bind to the router if not instanciated (altough approval can be done)
    (RouterProxy testRunnerProxy,) = mgo.ROUTER_FACTORY().instantiate(address(this), mgo.ROUTER_IMPLEMENTATION());
    AbstractRouter(address(testRunnerProxy)).bind(address(mgo));
    // user approves `mgo` to pull quote or base when doing a market order
    require(TransferLib.approveToken(quote, $(mgo.router(address(this))), type(uint).max));
    require(TransferLib.approveToken(base, $(mgo.router(address(this))), type(uint).max));

    cold_buyResult = mgo.take{value: 0.1 ether}(buyOrder);
    cold_sellResult = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(cold_buyResult.offerId * cold_sellResult.offerId > 0, "Resting offer failed to be published on mangrove");
    // mgo ask
    // 4 ┆ 1999 DAI  /  1 WETH 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker asks
    // 1 ┆ 2000 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 2 ┆ 2001 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 3 ┆ 2002 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // ------------------------------------------------------------------
    // mgo bid
    // 4 ┆ 1 WETH  /  1991 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker bids
    // 1 ┆ 1 WETH  /  1990 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 2 ┆ 1 WETH  /  1989 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 3 ┆ 1 WETH  /  1988 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
  }

  function test_admin() public {
    assertEq(mgv.governance(), mgo.admin(), "Invalid admin address");
  }

  function freshTaker(uint balBase, uint balQuote) internal returns (address fresh_taker) {
    fresh_taker = freshAddress("MgvOrderTester");
    deal($(quote), fresh_taker, balQuote);
    deal($(base), fresh_taker, balBase);
    deal(fresh_taker, 1 ether);
    activateOwnerRouter(base, MangroveOffer($(mgo)), fresh_taker);
    activateOwnerRouter(quote, MangroveOffer($(mgo)), fresh_taker);
  }

  ////////////////////////
  /// Tests taker side ///
  ////////////////////////

  function createBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = IOrderLogic.TakerOrder({
      olKey: olKey,
      orderType: TakerOrderType.IOC,
      fillWants: true,
      fillVolume: fillVolume,
      tick: tickFromPrice_e18(MID_PRICE - 1e18),
      expiryDate: 0, //NA
      offerId: 0,
      restingOrderGasreq: GASREQ,
      takerGivesLogic: AbstractRoutingLogic(address(0)),
      takerWantsLogic: AbstractRoutingLogic(address(0))
    });
  }

  /// At half the volume, but same price
  function createBuyOrderHalfVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createBuyOrder();
    order.fillVolume = fillVolume;
  }

  function createBuyOrderHigherPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createBuyOrder();
    // A high price so as to take ask_maker's offers
    order.fillVolume = fillVolume;
    order.tick = tickFromPrice_e18(MID_PRICE + 10000e18);
  }

  /// At lower price, same volume
  function createBuyOrderLowerPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createBuyOrder();
    order.fillVolume = fillVolume;
    order.tick = tickFromPrice_e18(MID_PRICE - 2e18);
  }

  function createBuyOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createBuyOrder();
    order.fillVolume = fillVolume;
    order.tick = tickFromPrice_e18(MID_PRICE - 9e18);
  }

  function createSellOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;

    order = IOrderLogic.TakerOrder({
      olKey: lo,
      orderType: TakerOrderType.IOC,
      fillWants: false,
      tick: tickFromPrice_e18(MID_PRICE - 9e18).negate(),
      fillVolume: fillVolume,
      expiryDate: 0, //NA
      offerId: 0,
      restingOrderGasreq: GASREQ,
      takerGivesLogic: AbstractRoutingLogic(address(0)),
      takerWantsLogic: AbstractRoutingLogic(address(0))
    });
  }

  function createSellOrderLowerPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createSellOrder();
    order.tick = tickFromPrice_e18(MID_PRICE - 8e18).negate();
    order.fillVolume = fillVolume;
  }

  function createSellOrderHalfVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createSellOrder();
    order.tick = tickFromPrice_e18(MID_PRICE - 9e18).negate();
    order.fillVolume = fillVolume;
  }

  function createSellOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createSellOrder();
    order.tick = tickFromPrice_e18(MID_PRICE - 1e18).negate();
    order.fillVolume = fillVolume;
  }

  function test_post_only_order_should_be_posted_and_not_make_market_order() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    buyOrder.orderType = TakerOrderType.PO;
    address fresh_taker = freshTaker(0, takerGives(buyOrder) * 2);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertGt(res.offerId, 0, "Resting offer failed to be published on mangrove");
    assertEq(res.takerGot, 0, "Taker should not have received any tokens");
    assertEq(res.takerGave, 0, "Taker should not have given any tokens");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_partial_filled_buy_order_is_transferred_to_taker() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    address fresh_taker = freshTaker(0, takerGives(buyOrder) * 2);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder) / 2), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder) / 2, "Incorrect partial fill of taker order");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "Funds were not transferred to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_partial_filled_buy_order_reverts_when_FoK_enabled() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    buyOrder.orderType = TakerOrderType.FOK;
    address fresh_taker = freshTaker(0, takerGives(buyOrder) * 2);
    vm.prank(fresh_taker);
    vm.expectRevert("mgvOrder/partialFill");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_order_reverts_when_expiry_date_is_reached() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    buyOrder.orderType = TakerOrderType.FOK;
    buyOrder.expiryDate = block.timestamp;
    address fresh_taker = freshTaker(0, takerGives(buyOrder) * 2);
    vm.prank(fresh_taker);
    vm.expectRevert("mgvOrder/expired");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_partial_filled_returns_value_and_remaining_inbound() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    address fresh_taker = freshTaker(0, takerGives(buyOrder));
    uint balBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(balBefore, fresh_taker.balance, "Take function did not return value to taker");
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder) / 2), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder) / 2, "Incorrect partial fill of taker order");
    assertEq(
      takerGives(buyOrder) - takerGives(buyOrder) / 2,
      quote.balanceOf(fresh_taker),
      "Take did not return remainder to taker"
    );
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_partial_filled_order_returns_bounty() public {
    ask_maker.shouldRevert(true);
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderHigherPrice();
    address fresh_taker = freshTaker(0, takerGives(buyOrder));
    uint balBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.bounty > 0, "Bounty should not be zero");
    assertEq(balBefore + res.bounty, fresh_taker.balance, "Take function did not return bounty");
  }

  function test_filled_resting_buy_order_ignores_resting_option_and_returns_value() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderHalfVolume();
    buyOrder.orderType = TakerOrderType.GTC;
    address fresh_taker = freshTaker(0, 4000 ether);
    uint nativeBalBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.offerId, 0, "There should be no resting order");
    assertEq(quote.balanceOf(fresh_taker), 4000 ether - takerGives(buyOrder), "incorrect quote balance");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "incorrect base balance");
    assertEq(fresh_taker.balance, nativeBalBefore, "value was not returned to taker");
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder)), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder), "Incorrect partial fill of taker order");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_filled_resting_buy_order_with_FoK_succeeds_and_returns_provision() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderHalfVolume();
    buyOrder.orderType = TakerOrderType.FOK;
    address fresh_taker = freshTaker(0, takerGives(buyOrder));
    uint nativeBalBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.offerId, 0, "There should be no resting order");
    assertEq(quote.balanceOf(fresh_taker), 0, "incorrect quote balance");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "incorrect base balance");
    assertEq(fresh_taker.balance, nativeBalBefore, "value was not returned to taker");
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder)), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder), "Incorrect partial fill of taker order");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_taken_resting_order_reused() public {
    // Arrange - Take resting order
    vm.prank($(sell_taker));
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, Tick.wrap(MAX_TICK), 1000000 ether, true);
    assertTrue(takerGot > 0 && bounty == 0, "marketOrder failed");
    assertFalse(mgv.offers(lo, cold_buyResult.offerId).isLive(), "Offer should be taken and not live");

    // Act - Create new resting order, but reuse id
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.offerId = cold_buyResult.offerId;
    buyOrder.orderType = TakerOrderType.GTC;

    expectFrom($(mgo));
    logOrderData($(this), buyOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);

    // Assert
    Offer offer = mgv.offers(lo, res.offerId);
    assertEq(res.offerId, buyOrder.offerId, "OfferId should be reused");
    assertTrue(offer.isLive(), "Offer be live");
    assertEq(offer.gives(), makerGives(buyOrder), "Incorrect offer gives");
    assertApproxEqAbs(offer.wants(), makerWants(buyOrder), 1, "Incorrect offer wants");
    assertEq(offer.tick(), buyOrder.tick.negate(), "Incorrect offer price");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_taken_resting_order_not_reused_if_live() public {
    // Arrange
    assertTrue(mgv.offers(lo, cold_buyResult.offerId).isLive(), "Offer should live");

    // Act - Create new resting order, but reuse id
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.offerId = cold_buyResult.offerId;
    buyOrder.orderType = TakerOrderType.GTC;

    // Assert
    vm.expectRevert("mgvOrder/offerAlreadyActive");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_taken_resting_order_not_reused_if_not_owned() public {
    // Arrange - Take resting order
    vm.prank($(sell_taker));
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, Tick.wrap(MAX_TICK), 1000000 ether, true);
    assertTrue(takerGot > 0 && bounty == 0, "marketOrder failed");
    assertFalse(mgv.offers(lo, cold_buyResult.offerId).isLive(), "Offer should be taken and not live");

    // Act/assert - Create new resting order, but reuse id
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.offerId = cold_buyResult.offerId;
    buyOrder.orderType = TakerOrderType.GTC;

    address router = $(mgo.router($(sell_taker)));
    vm.prank($(sell_taker));
    TransferLib.approveToken(quote, router, takerGives(buyOrder) + makerGives(buyOrder));
    deal($(quote), $(sell_taker), takerGives(buyOrder) + makerGives(buyOrder));

    vm.expectRevert("AccessControlled/Invalid");
    // Not owner
    vm.prank($(sell_taker));
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  ///////////////////////
  /// Test maker side ///
  ///////////////////////

  function logOrderData(address taker, IOrderLogic.TakerOrder memory tko) internal {
    emit MangroveOrderStart(
      tko.olKey.hash(),
      taker,
      tko.tick,
      tko.orderType,
      tko.fillVolume,
      tko.fillWants,
      tko.offerId,
      tko.takerWantsLogic,
      tko.takerGivesLogic
    );
  }

  function test_partial_fill_buy_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrder();
    buyOrder.orderType = TakerOrderType.GTC;

    IOrderLogic.TakerOrderResult memory expectedResult = IOrderLogic.TakerOrderResult({
      takerGot: reader.minusFee(lo, 1 ether),
      takerGave: takerGives(buyOrder) / 2,
      bounty: 0,
      fee: 1 ether - reader.minusFee(lo, 1 ether),
      offerId: 5,
      offerWriteData: "offer/created"
    });

    address fresh_taker = freshTaker(0, takerGives(buyOrder));
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(fresh_taker, buyOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(lo, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(lo.hash(), res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(
      quote.balanceOf(fresh_taker), takerGives(buyOrder) - expectedResult.takerGave, "Incorrect remaining quote balance"
    );
    assertEq(base.balanceOf(fresh_taker), reader.minusFee(olKey, 1 ether), "Incorrect obtained base balance");
    assertEq(res.offerWriteData, expectedResult.offerWriteData, "Incorrect offer write data");
    assertEq(res.bounty, 0, "Bounty should be zero");
    // checking price of offer
    Offer offer = mgv.offers(lo, res.offerId);
    OfferDetail detail = mgv.offerDetails(lo, res.offerId);
    assertEq(offer.gives(), makerGives(buyOrder) / 2, "Incorrect offer gives");
    assertEq(offer.wants(), makerWants(buyOrder) / 2 + 1, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_empty_fill_buy_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.orderType = TakerOrderType.GTC;

    address fresh_taker = freshTaker(0, takerGives(buyOrder));
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(fresh_taker, buyOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(lo, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(lo.hash(), res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(quote.balanceOf(fresh_taker), takerGives(buyOrder), "Incorrect remaining quote balance");
    assertEq(base.balanceOf(fresh_taker), 0, "Incorrect obtained base balance");
    // checking price of offer
    Offer offer = mgv.offers(lo, res.offerId);
    OfferDetail detail = mgv.offerDetails(lo, res.offerId);
    assertEq(offer.gives(), makerGives(buyOrder), "Incorrect offer gives");
    assertApproxEqAbs(offer.wants(), makerWants(buyOrder), 1, "Incorrect offer wants");
    assertEq(offer.tick(), buyOrder.tick.negate(), "Incorrect offer price");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_partial_fill_sell_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTC;

    IOrderLogic.TakerOrderResult memory expectedResult = IOrderLogic.TakerOrderResult({
      takerGot: reader.minusFee(lo, takerWants(sellOrder) / 2) + 1,
      takerGave: takerGives(sellOrder) / 2 + 1,
      bounty: 0,
      fee: takerWants(sellOrder) / 2 - reader.minusFee(lo, takerWants(sellOrder) / 2) - 1,
      offerId: 5,
      offerWriteData: "offer/created"
    });

    address fresh_taker = freshTaker(takerGives(sellOrder), 0);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(fresh_taker, sellOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(olKey, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(olKey.hash(), res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(
      base.balanceOf(fresh_taker), takerGives(sellOrder) - expectedResult.takerGave, "Incorrect remaining base balance"
    );
    assertEq(quote.balanceOf(fresh_taker), expectedResult.takerGot, "Incorrect obtained quote balance");
    assertEq(res.offerWriteData, expectedResult.offerWriteData, "Incorrect offer write data");
    // checking price of offer
    Offer offer = mgv.offers(olKey, res.offerId);
    OfferDetail detail = mgv.offerDetails(olKey, res.offerId);
    assertEq(offer.gives(), makerGives(sellOrder) / 2 - 1, "Incorrect offer gives");

    assertApproxEqRel(offer.wants(), makerWants(sellOrder) / 2, 1e4, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_partial_fill_sell_with_resting_order_below_density() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTC;
    sellOrder.fillVolume = 1 ether; // the amount that will be filled, used to calculate expected taker result

    IOrderLogic.TakerOrderResult memory expectedResult = IOrderLogic.TakerOrderResult({
      takerGot: reader.minusFee(lo, takerWants(sellOrder)) + 1,
      takerGave: 1 ether,
      bounty: 0,
      fee: takerWants(sellOrder) / 2 - reader.minusFee(lo, takerWants(sellOrder) / 2) - 1,
      offerId: 5,
      offerWriteData: "mgv/writeOffer/density/tooLow"
    });

    sellOrder.fillVolume = 1 ether + 10; // ask for a tiny bit more, so the remaining too low to repost

    address fresh_taker = freshTaker(takerGives(sellOrder), 0);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(fresh_taker, sellOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(res.offerId == 0, "Offer should not be posted");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertEq(res.offerWriteData, expectedResult.offerWriteData, "Incorrect offer write data");
    assertEq(fresh_taker.balance, nativeBalBefore, "No provision should be transferred");
    // checking mappings
    assertEq(
      base.balanceOf(fresh_taker),
      takerGives(sellOrder) - expectedResult.takerGave - 1,
      "Incorrect remaining base balance"
    );
    assertEq(quote.balanceOf(fresh_taker), expectedResult.takerGot, "Incorrect obtained quote balance");
  }

  function test_empty_fill_sell_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrderLowerPrice();
    sellOrder.orderType = TakerOrderType.GTC;

    address fresh_taker = freshTaker(2 ether, 0);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(fresh_taker, sellOrder);
    expectFrom($(mgo));
    emit MangroveOrderComplete();

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(olKey, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(olKey.hash(), res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(base.balanceOf(fresh_taker), takerGives(sellOrder), "Incorrect remaining base balance");
    assertEq(quote.balanceOf(fresh_taker), 0, "Incorrect obtained quote balance");
    // checking price of offer
    Offer offer = mgv.offers(olKey, res.offerId);
    OfferDetail detail = mgv.offerDetails(olKey, res.offerId);
    assertEq(offer.gives(), makerGives(sellOrder), "Incorrect offer gives");
    assertEq(offer.wants(), makerWants(sellOrder), "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_resting_order_with_expiry_date_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTC;
    sellOrder.expiryDate = block.timestamp + 1;
    address fresh_taker = freshTaker(2 ether, 0);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);
    RenegingForwarder.Condition memory cond = mgo.reneging(olKey.hash(), res.offerId);
    assertEq(cond.date, block.timestamp + 1, "Incorrect expiry");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  function test_resting_buy_order_for_blacklisted_reserve_for_inbound_reverts() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrderHalfVolume();
    sellOrder.orderType = TakerOrderType.GTC;
    address fresh_taker = freshTaker(1 ether, 0);
    vm.mockCall(
      $(quote),
      abi.encodeWithSelector(
        quote.transferFrom.selector, $(mgo), fresh_taker, reader.minusFee(lo, takerWants(sellOrder))
      ),
      abi.encode(false)
    );
    vm.expectRevert("mgvOrder/pushFailed");
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  function test_resting_buy_order_failing_to_post_returns_tokens_and_provision() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTC;
    address fresh_taker = freshTaker(2 ether, 0);
    uint oldNativeBal = fresh_taker.balance;
    // pretend new offer failed for some reason
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOfferByTick.selector), abi.encode(uint(0)));
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
    assertEq(fresh_taker.balance, oldNativeBal, "Taker's provision was not returned");
  }

  function test_restingOrder_that_fail_to_post_revert_if_no_partialFill() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTCE;
    address fresh_taker = freshTaker(2 ether, 0);
    // pretend new offer failed for some reason
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOfferByTick.selector), abi.encode(uint(0)));
    vm.expectRevert("mgvOrder/RestingOrderFailed");
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  function test_taker_unable_to_receive_eth_makes_tx_throw_if_resting_order_could_not_be_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = createSellOrder();
    sellOrder.orderType = TakerOrderType.GTC;
    TestSender sender = new TestSender();
    vm.deal($(sender), 1 ether);

    deal($(base), $(sender), 2 ether);
    sender.refuseNative();
    activateOwnerRouter(base, MangroveOffer($(mgo)), $(sender));
    // mocking MangroveOrder failure to post resting offer
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOfferByTick.selector), abi.encode(uint(0)));
    /// since `sender` throws on `receive()`, this should fail.
    vm.expectRevert("mgvOrder/refundFail");
    vm.prank($(sender));
    // complete fill will not lead to a resting order
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  //////////////////////////////////////
  /// Test resting order consumption ///
  //////////////////////////////////////

  function test_resting_buy_offer_can_be_partially_filled() public {
    // sniping resting sell offer: 4 ┆ 1999 DAI  /  1 WETH 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    uint oldBaseBal = base.balanceOf($(this));
    uint oldQuoteBal = quote.balanceOf($(this)); // quote balance of test runner

    Offer offer = mgv.offers(lo, cold_buyResult.offerId);
    Tick tick = mgv.offers(lo, cold_buyResult.offerId).tick();

    vm.prank($(sell_taker));
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgv.marketOrderByTick(lo, tick, 1000 ether, true);
    // sell_taker.takeWithInfo({takerWants: 1000 ether, offerId: cold_buyResult.offerId});

    // no fail
    assertEq(bounty, 0, "Bounty should be zero");
    // offer delivers
    assertEq(takerGot, 1000 ether - fee, "Incorrect received amount for seller taker");
    // inbound token forwarded to test runner
    assertEq(base.balanceOf($(this)), oldBaseBal + takerGave, "Incorrect base balance");
    // outbound taken from test runner
    assertEq(quote.balanceOf($(this)), oldQuoteBal - (takerGot + fee), "Incorrect quote balance");
    // checking residual
    Offer offer_ = mgv.offers(lo, cold_buyResult.offerId);
    assertEq(offer_.gives(), offer.gives() - (takerGot + fee), "Incorrect residual");
  }

  function test_resting_buy_offer_can_be_fully_consumed_at_minimum_approval() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.orderType = TakerOrderType.GTC;
    TransferLib.approveToken(quote, $(mgo.router(address(this))), takerGives(buyOrder) + makerGives(buyOrder));
    IOrderLogic.TakerOrderResult memory buyResult = mgo.take{value: 0.1 ether}(buyOrder);

    assertEq(buyResult.bounty, 0, "Bounty should be zero");
    assertTrue(buyResult.offerId > 0, "Resting order should succeed");

    Tick tick = mgv.offers(lo, buyResult.offerId).tick();

    vm.prank($(sell_taker));
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, tick, 40000 ether, true);

    assertEq(bounty, 0, "Bounty should be zero");
    assertTrue(takerGot > 0, "Offer should succeed");
  }

  function test_failing_resting_offer_releases_uncollected_provision() public {
    uint provision = mgo.provisionOf(lo, cold_buyResult.offerId);
    // empty quotes so that cold buy offer fails
    Tick tick = mgv.offers(lo, cold_buyResult.offerId).tick();
    deal($(quote), address(this), 0);
    _gas();
    vm.prank($(sell_taker));
    (,, uint bounty,) = mgv.marketOrderByTick(lo, tick, 1991, false);
    uint g = gas_(true);

    assertTrue(bounty > 0, "offer should be cleaned");
    assertTrue(
      provision > mgo.provisionOf(lo, cold_buyResult.offerId), "Remaining provision should be less than original"
    );
    assertTrue(mgo.provisionOf(lo, cold_buyResult.offerId) > 0, "Remaining provision should not be 0");
    assertTrue(bounty > g * mgv.global().gasprice(), "taker not compensated");
    console.log("Taker gained %s native", toFixed(bounty - g * mgv.global().gasprice(), 18));
  }

  function test_offer_succeeds_when_time_is_not_expired() public {
    mgo.setReneging(lo.hash(), cold_buyResult.offerId, block.timestamp + 1, 0);
    Tick tick = mgv.offers(lo, cold_buyResult.offerId).tick();
    vm.prank($(sell_taker));
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, tick, 1991, true);
    assertTrue(takerGot > 0, "offer failed");
    assertEq(bounty, 0, "Bounty should be zero");
  }

  function test_offer_reneges_when_time_is_expired() public {
    mgo.setReneging(lo.hash(), cold_buyResult.offerId, block.timestamp, 0);
    vm.warp(block.timestamp + 1);
    Tick tick = mgv.offers(lo, cold_buyResult.offerId).tick();
    expectFrom($(mgo));
    emit LogIncident({
      olKeyHash: lo.hash(),
      offerId: 4,
      makerData: "RenegingForwarder/expired",
      mgvData: "mgv/makerRevert"
    });

    vm.prank($(sell_taker));
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, tick, 1991, true);
    assertTrue(takerGot == 0, "offer should have failed");
    assertTrue(bounty > 0, "taker not compensated");
  }
  //////////////////////////////
  /// Tests offer management ///
  //////////////////////////////

  function test_user_can_retract_resting_offer() public {
    uint userWeiBalanceOld = $(this).balance;
    uint credited = mgo.retractOffer(lo, cold_buyResult.offerId, true);
    assertEq($(this).balance, userWeiBalanceOld + credited, "Incorrect provision received");
  }

  function test_offer_owner_can_set_expiry() public {
    expectFrom($(mgo));
    emit SetReneging(lo.hash(), cold_buyResult.offerId, 42, 0);
    mgo.setReneging(lo.hash(), cold_buyResult.offerId, 42, 0);
    RenegingForwarder.Condition memory cond = mgo.reneging(lo.hash(), cold_buyResult.offerId);
    assertEq(cond.date, 42, "expiry date was not set");
  }

  function test_only_offer_owner_can_set_expiry() public {
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.setReneging(lo.hash(), cold_buyResult.offerId, 42, 0);
  }

  function test_offer_owner_can_update_offer() public {
    mgo.updateOffer(lo, Tick.wrap(100), 2000 ether, 10, cold_buyResult.offerId);
    Offer offer = mgv.offers(lo, cold_buyResult.offerId);
    assertEq(Tick.unwrap(offer.tick()), 100, "Incorrect updated price");
    assertEq(offer.gives(), 2000 ether, "Incorrect updated gives");
    assertEq(mgo.ownerOf(lo.hash(), cold_buyResult.offerId), $(this), "Owner should not have changed");
  }

  function test_only_offer_owner_can_update_offer() public {
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.updateOffer(lo, Tick.wrap(0), 2000 ether, cold_buyResult.offerId, 10);
  }

  //////////////////////////////
  /// Gas requirements tests ///
  //////////////////////////////

  function test_mockup_routing_gas_cost() public {
    AbstractRouter router = mgo.router(address(this));

    // making quote balance hot to mock taker's transfer
    quote.transfer($(mgo), 1);

    uint g = gasleft();
    vm.startPrank($(mgo));
    quote.approve($(router), 1);
    uint pushed = router.push(RL.createOrder({token: quote, fundOwner: address(this)}), 1);
    vm.stopPrank();

    uint push_cost = g - gasleft();
    assertEq(pushed, 1, "Push failed");

    vm.prank($(mgo));
    g = gasleft();
    uint pulled = router.pull(RL.createOrder({token: base, fundOwner: address(this)}), 1, true);
    uint pull_cost = g - gasleft();
    assertEq(pulled, 1, "Pull failed");

    console.log("Gas cost: %d (pull: %d g.u, push: %d g.u)", pull_cost + push_cost, pull_cost, push_cost);
  }

  function test_mockup_offerLogic_gas_cost() public {
    (MgvLib.SingleOrder memory sellOrder, MgvLib.OrderResult memory result) = mockPartialFillSellOrder({
      takerWants: 1991 ether / 2,
      tick: TickLib.tickFromVolumes(0.5 ether, 1991 ether / 2),
      partialFill: 2,
      _olBaseQuote: olKey,
      makerData: ""
    });
    // prank a fresh taker to avoid heating test runner balance
    vm.prank($(mgv));
    base.transferFrom(address(sell_taker), $(mgv), sellOrder.takerGives);
    vm.prank($(mgv));
    base.transfer($(mgo), sellOrder.takerGives);

    sellOrder.offerId = cold_buyResult.offerId;
    vm.prank($(mgv));
    _gas();
    mgo.makerExecute(sellOrder);
    uint exec_gas = gas_(true);
    // since offer reposts itself, making offer info, mgo credit on mangrove and mgv config hot in storage
    mgv.config(lo);
    mgv.offers(lo, sellOrder.offerId);
    mgv.offerDetails(lo, sellOrder.offerId);
    mgv.fund{value: 1}($(mgo));

    vm.prank($(mgv));
    _gas();
    mgo.makerPosthook(sellOrder, result);
    uint posthook_gas = gas_(true);
    console.log(
      "MgvOrder's logic is %d (makerExecute: %d, makerPosthook:%d)", exec_gas + posthook_gas, exec_gas, posthook_gas
    );
  }

  // TODO: test gas cost of taker order
  function test_empirical_offer_gas_cost() public {
    // resting order buys 1 ether for (MID_PRICE-9 ether) dai
    // fresh taker sells 0.5 ether for 900 dai for any gasreq
    Tick tick = mgv.offers(lo, cold_buyResult.offerId).tick();
    vm.prank(address(sell_taker));
    _gas();
    // cannot use TestTaker functions that have additional gas cost
    // simply using sell_taker's approvals and already filled balances
    (uint takerGot,, uint bounty,) = mgv.marketOrderByTick(lo, tick, 0.5 ether, true);
    gas_();
    assertEq(bounty, 0, "Bounty should be zero");
    assertTrue(takerGot > 0, "offer should succeed");
    assertTrue(mgv.offers(lo, cold_buyResult.offerId).gives() > 0, "Update failed");
  }

  /////////////////////////////////////
  ///   Test routing logic (aave)   ///
  /////////////////////////////////////

  function aavePool() internal view returns (IPool) {
    return IPool(IPoolAddressesProvider(fork.get("AaveAddressProvider")).getPool());
  }

  function aaveOverlyingOf(IERC20 token) internal view returns (IERC20) {
    return IERC20(aavePool().getReserveData(address(token)).aTokenAddress);
  }

  function createFullAaveBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createBuyOrder();
    order.restingOrderGasreq = AAVE_GASREQ;
    order.takerGivesLogic = aaveLogic;
    order.takerWantsLogic = aaveLogic;
  }

  function createAaveGivesBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createBuyOrder();
    order.takerGivesLogic = aaveLogic;
    order.restingOrderGasreq = AAVE_GASREQ;
  }

  function createAaveWantsBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createBuyOrder();
    order.takerWantsLogic = aaveLogic;
    order.restingOrderGasreq = AAVE_GASREQ;
  }

  // take from user reserve and deposit on aave
  function test_partial_filled_buy_order_is_transferred_to_taker_on_aave() public {
    IOrderLogic.TakerOrder memory buyOrder = createAaveWantsBuyOrder();
    address fresh_taker = freshTaker(0, takerGives(buyOrder) * 2);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder) / 2), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder) / 2, "Incorrect partial fill of taker order");
    assertEq(aaveOverlyingOf(base).balanceOf(fresh_taker), res.takerGot, "Funds were not transferred to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  // take from aave and deposit on user reserve
  function test_partial_filled_buy_order_from_aave_is_transferred_to_taker() public {
    IOrderLogic.TakerOrder memory buyOrder = createAaveGivesBuyOrder();
    uint amount = takerGives(buyOrder) * 2;
    address fresh_taker = freshTaker(0, amount);
    vm.startPrank(fresh_taker);
    quote.approve(address(aavePool()), amount);
    aavePool().supply(address(quote), amount, fresh_taker, 0);
    require(TransferLib.approveToken(aaveOverlyingOf(quote), $(mgo.router(fresh_taker)), type(uint).max));
    uint startBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    uint endBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    vm.stopPrank();
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder) / 2), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder) / 2, "Incorrect partial fill of taker order");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "Funds were not transferred to taker");
    assertApproxEqAbs(startBalance - endBalance, res.takerGave, 1, "Funds were not transferred from aave to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  // take from aave and deposit on aave
  function test_partial_filled_buy_order_from_aave_is_transferred_to_taker_on_aave() public {
    IOrderLogic.TakerOrder memory buyOrder = createFullAaveBuyOrder();
    uint amount = takerGives(buyOrder) * 2;
    address fresh_taker = freshTaker(0, amount);
    vm.startPrank(fresh_taker);
    quote.approve(address(aavePool()), amount);
    aavePool().supply(address(quote), amount, fresh_taker, 0);
    require(TransferLib.approveToken(aaveOverlyingOf(quote), $(mgo.router(fresh_taker)), type(uint).max));
    uint startBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    uint endBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    vm.stopPrank();
    assertEq(res.takerGot, reader.minusFee(olKey, takerWants(buyOrder) / 2), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, takerGives(buyOrder) / 2, "Incorrect partial fill of taker order");
    assertEq(aaveOverlyingOf(base).balanceOf(fresh_taker), res.takerGot, "Funds were not transferred to taker");
    assertApproxEqAbs(startBalance - endBalance, res.takerGave, 1, "Funds were not transferred from aave to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
  }

  ///////////////////////////////////////////////////////
  ///   Test routing logic (aave) order consumption   ///
  ///////////////////////////////////////////////////////

  function getBestTick() internal view returns (Tick tick) {
    // trick to set the lowest price of the market once posting
    // we are setting the opposite tick as we are first trying market order on the other side of the book
    // since it is a PO, it will not check the other side of the book anyway
    uint bestOfferId = mgv.best(lo);
    tick = mgv.offers(lo, bestOfferId).tick();
    tick = Tick.wrap(-Tick.unwrap(tick) + 1);
  }

  function createTakeableAaveGivesBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createAaveGivesBuyOrder();
    order.orderType = TakerOrderType.PO;
    order.tick = getBestTick();
  }

  function createTakeableAaveWantsBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createAaveWantsBuyOrder();
    order.orderType = TakerOrderType.PO;
    order.tick = getBestTick();
  }

  function createTakeableAaveFullOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    order = createFullAaveBuyOrder();
    order.orderType = TakerOrderType.PO;
    order.tick = getBestTick();
  }

  function test_order_consumption_with_routing_logic_from_aave_and_to_wallet() public {
    IOrderLogic.TakerOrder memory buyOrder = createTakeableAaveGivesBuyOrder();
    uint amount = takerGives(buyOrder) * 2;
    address fresh_taker = freshTaker(0, amount);

    vm.startPrank(fresh_taker);
    quote.approve(address(aavePool()), amount);
    aavePool().supply(address(quote), amount, fresh_taker, 0);
    require(TransferLib.approveToken(aaveOverlyingOf(quote), $(mgo.router(fresh_taker)), type(uint).max));
    uint startBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    vm.stopPrank();

    assertEq(res.takerGot, 0, "Order was partially filled or filled");
    assertEq(res.takerGave, 0, "Incorrect partial fill of taker order");
    assertEq(aaveOverlyingOf(quote).balanceOf(fresh_taker), amount, "Funds were not transferred to taker");
    assertEq(base.balanceOf(fresh_taker), 0, "Funds were not transferred to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertGt(res.offerId, 0, "Offer should be posted");

    Tick tick = mgv.offers(lo, res.offerId).tick();

    vm.prank($(sell_taker));
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgv.marketOrderByTick(lo, tick, 1000 ether, true);

    assertEq(bounty, 0, "Bounty should be zero");
    assertEq(
      aaveOverlyingOf(quote).balanceOf(fresh_taker),
      startBalance - (takerGot + fee),
      "Funds were not transferred to taker"
    );
    assertEq(base.balanceOf(fresh_taker), takerGave, "Funds were not transferred to maker");
  }

  function test_order_consumption_with_routing_logic_from_wallet_and_to_aave() public {
    IOrderLogic.TakerOrder memory buyOrder = createTakeableAaveWantsBuyOrder();
    uint amount = takerGives(buyOrder) * 2;
    address fresh_taker = freshTaker(0, amount);

    vm.startPrank(fresh_taker);
    require(TransferLib.approveToken(quote, $(mgo.router(fresh_taker)), type(uint).max));
    uint startBalance = quote.balanceOf(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    vm.stopPrank();

    assertEq(res.takerGot, 0, "Order was partially filled or filled");
    assertEq(res.takerGave, 0, "Incorrect partial fill of taker order");
    assertEq(quote.balanceOf(fresh_taker), amount, "Funds were transferred to taker");
    assertEq(base.balanceOf(fresh_taker), 0, "Funds were transferred to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertGt(res.offerId, 0, "Offer should be posted");

    Tick tick = mgv.offers(lo, res.offerId).tick();

    vm.prank($(sell_taker));
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgv.marketOrderByTick(lo, tick, 1000 ether, true);

    assertEq(bounty, 0, "Bounty should be zero");
    assertEq(aaveOverlyingOf(base).balanceOf(fresh_taker), takerGave, "Funds were not transferred to taker");
    assertEq(quote.balanceOf(fresh_taker), startBalance - (takerGot + fee), "Funds were not transferred to maker");
  }

  function test_order_consumption_with_routing_logic_from_aave_and_to_aave() public {
    IOrderLogic.TakerOrder memory buyOrder = createTakeableAaveFullOrder();
    uint amount = takerGives(buyOrder) * 2;
    address fresh_taker = freshTaker(0, amount);

    vm.startPrank(fresh_taker);
    quote.approve(address(aavePool()), amount);
    aavePool().supply(address(quote), amount, fresh_taker, 0);
    require(TransferLib.approveToken(aaveOverlyingOf(quote), $(mgo.router(fresh_taker)), type(uint).max));
    uint startBalance = aaveOverlyingOf(quote).balanceOf(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    vm.stopPrank();

    assertEq(res.takerGot, 0, "Order was partially filled or filled");
    assertEq(res.takerGave, 0, "Incorrect partial fill of taker order");
    assertEq(aaveOverlyingOf(quote).balanceOf(fresh_taker), amount, "Funds were not transferred to taker");
    assertEq(aaveOverlyingOf(base).balanceOf(fresh_taker), 0, "Funds were not transferred to taker");
    assertEq(res.bounty, 0, "Bounty should be zero");
    assertGt(res.offerId, 0, "Offer should be posted");

    Tick tick = mgv.offers(lo, res.offerId).tick();

    vm.prank($(sell_taker));
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgv.marketOrderByTick(lo, tick, 1000 ether, true);

    assertEq(bounty, 0, "Bounty should be zero");
    assertEq(
      aaveOverlyingOf(quote).balanceOf(fresh_taker),
      startBalance - (takerGot + fee),
      "Funds were not transferred to taker"
    );
    assertEq(aaveOverlyingOf(base).balanceOf(fresh_taker), takerGave, "Funds were not transferred to maker");
  }
}
