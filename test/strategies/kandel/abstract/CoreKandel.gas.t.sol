// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./KandelTest.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TickLib, Tick, MAX_TICK} from "mgv_lib/TickLib.sol";

abstract contract CoreKandelGasTest is KandelTest {
  uint internal completeFill_;
  uint internal partialFill_;
  PinnedPolygonFork internal fork;

  function setUp() public virtual override {
    super.setUp();
    vm.prank(maker);
    kdl.setCompoundRates(10 ** PRECISION, 10 ** PRECISION);
    // non empty balances for tests
    deal($(base), address(this), 1);
    base.approve($(mgv), 1);
  }

  function __deployKandel__(address deployer, address) internal virtual override returns (GeometricKandel kdl_) {
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      //FIXME: measure
      gasreq: 260_000,
      gasprice: 0,
      reserveId: address(0)
    });
  }

  function __setForkEnvironment__() internal virtual override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    options.density = 2 ** 32;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function densifyMissing(uint index, uint fold) internal {
    IndexStatus memory idx = getStatus(index);
    if (idx.status == OfferStatus.Bid) {
      // densify Ask position
      densify(address(base), address(quote), idx.bid.gives(), idx.bid.wants(), 0, fold, address(this));
    } else {
      if (idx.status == OfferStatus.Ask) {
        densify(address(quote), address(base), idx.ask.gives(), idx.ask.wants(), 0, fold, address(this));
      }
    }
  }

  function test_log_mgv_config() public view {
    (, MgvStructs.LocalPacked local) = mgv.config($(base), $(quote));
    console.log("offer_gasbase", local.offer_gasbase());
    console.log("kandel gasreq", kdl.offerGasreq());
  }

  function test_complete_fill_bid_order() public {
    uint completeFill = completeFill_;
    address baseAddress = $(base);
    address quoteAddress = $(quote);
    vm.prank(taker);
    _gas();
    // taking partial fill to have gas cost of reposting
    (uint takerGot,,,) = mgv.marketOrderByTick(baseAddress, quoteAddress, MAX_TICK, completeFill, true);
    gas_();
    require(takerGot > 0);
  }

  function bid_order_length_n(uint n) internal {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    uint volume = completeFill * (n - 1) + partialFill;
    address baseAddress = $(base);
    address quoteAddress = $(quote);

    vm.prank(taker);
    _gas();
    (uint takerGot,,,) = mgv.marketOrderByTick(baseAddress, quoteAddress, MAX_TICK, volume, true);
    uint g = gas_(true);
    require(takerGot > 0);
    console.log(n, ",", g);
    assertStatus(5 - n, OfferStatus.Bid);
  }

  function test_bid_order_length_1() public {
    bid_order_length_n(1);
  }

  function test_bid_order_length_2() public {
    bid_order_length_n(2);
  }

  function test_bid_order_length_3() public {
    bid_order_length_n(3);
  }

  function test_bid_order_length_4() public {
    bid_order_length_n(4);
  }

  function test_bid_order_length_5() public {
    bid_order_length_n(5);
  }

  function test_offerLogic_partialFill_cost() public {
    // take Ask #5
    uint gasreq = kdl.offerGasreq();
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 6);
    // making quote hot
    vm.prank($(mgv));
    base.transferFrom(address(this), $(mgv), 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants() / 2,
      takerWants: ask.gives() / 2,
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 6);
    order.offer = ask;
    // making mgv mappings hot
    mgv.config($(base), $(quote));
    mgv.config($(quote), $(base));

    vm.prank($(mgv));
    _gas();
    kdl.makerExecute(order);
    uint g = gas_(true);
    assertTrue(gasreq >= g, "Execute ran out of gas!");
    console.log("makerExecute", g);

    gasreq -= g;
    vm.prank($(mgv));
    _gas();
    kdl.makerPosthook(order, result);
    g = gas_(true);
    assertTrue(gasreq >= g, "Posthook ran out of gas!");
    console.log("makerPosthook", g);
    assertStatus(6, OfferStatus.Ask);
    assertStatus(5, OfferStatus.Crossed);
  }
}
