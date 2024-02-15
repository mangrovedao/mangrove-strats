// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {
  MangroveOrder as MgvOrder,
  SmartRouter,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {IOrderLogic} from "@mgv-strats/src/strategies/interfaces/IOrderLogic.sol";
import {TakerOrderType} from "@mgv-strats/src/strategies/TakerOrderLib.sol";
import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

library TickNegator {
  function negate(Tick tick) internal pure returns (Tick) {
    return Tick.wrap(-Tick.unwrap(tick));
  }
}

contract UniV3_Test is StratTest {
  using TickNegator for Tick;

  MgvOrder public mgo;

  TestTaker public sell_taker;
  TestMaker public ask_maker;

  TestMaker public bid_maker;

  uint constant MID_PRICE = 2000e18;
  uint constant GASREQ = 1_000_000;

  IOrderLogic.TakerOrderResult internal cold_buyResult;
  IOrderLogic.TakerOrderResult internal cold_sellResult;

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

  function createBuyOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createBuyOrder();
    order.fillVolume = fillVolume;
    order.tick = tickFromPrice_e18(MID_PRICE - 9e18);
  }

  function createSellOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createSellOrder();
    order.tick = tickFromPrice_e18(MID_PRICE - 1e18).negate();
    order.fillVolume = fillVolume;
  }

  function tickFromPrice_e18(uint priceE18) internal pure returns (Tick tick) {
    (uint mantissa, uint exp) = TickLib.ratioFromVolumes(priceE18, 1e18);
    tick = TickLib.tickFromRatio(mantissa, int(exp));
  }

  function setUp() public override {
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = new TestToken(address(this), "WETH", "WETH", 18);
    quote = new TestToken(address(this), "DAI", "DAI", 18);
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();
    setupMarket(olKey);

    RouterProxyFactory factory = new RouterProxyFactory();

    // this contract is admin of MgvOrder and its router
    mgo = new MgvOrder(IMangrove(payable(mgv)), factory, $(this));
    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)

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
}
