// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {KandelTest} from "./KandelTest.t.sol";
import {Local, OLKey, Offer, MgvLib} from "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {Kandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

abstract contract CoreKandelGasTest is KandelTest {
  uint internal completeFill_;
  uint internal partialFill_;
  PinnedPolygonFork internal fork;

  function setUp() public virtual override {
    super.setUp();
    vm.prank(maker);
    // non empty balances for tests
    deal($(base), address(this), 1);
    base.approve($(mgv), 1);
  }

  function __deployKandel__(address deployer, address) internal virtual override returns (GeometricKandel kdl_) {
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      olKeyBaseQuote: olKey,
      //FIXME: measure
      gasreq: 260_000,
      reserveId: address(0)
    });
  }

  function __setForkEnvironment__() internal virtual override {
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();
    setupMarket(olKey);
  }

  function densifyMissing(uint index, uint fold) internal {
    IndexStatus memory idx = getStatus(index);
    if (idx.status == OfferStatus.Bid) {
      // densify Ask position
      densify(olKey, idx.bid.tick(), idx.bid.gives(), 0, fold, address(this));
    } else {
      if (idx.status == OfferStatus.Ask) {
        densify(lo, idx.ask.tick(), idx.ask.gives(), 0, fold, address(this));
      }
    }
  }

  function test_log_mgv_config() public view {
    (, Local local) = mgv.config(olKey);
    console.log("offer_gasbase", local.offer_gasbase());
    console.log("kandel gasreq", kdl.offerGasreq());
  }

  function test_complete_fill_bid_order() public {
    uint completeFill = completeFill_;
    OLKey memory _olKey = olKey;
    vm.prank(taker);
    _gas();
    // taking partial fill to have gas cost of reposting
    (uint takerGot,,,) = mgv.marketOrderByTick(_olKey, Tick.wrap(MAX_TICK), completeFill, true);
    gas_();
    require(takerGot > 0, "offer should succeed");
  }

  function bid_order_length_n(uint n) internal {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    uint volume = completeFill * (n - 1) + partialFill;
    OLKey memory _olKey = olKey;

    vm.prank(taker);
    _gas();
    (uint takerGot,,,) = mgv.marketOrderByTick(_olKey, Tick.wrap(MAX_TICK), volume, true);
    uint g = gas_(true);
    require(takerGot > 0, "offer should succeed");
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
    Offer ask = kdl.getOffer(Ask, 6);
    // making quote hot
    vm.prank($(mgv));
    base.transferFrom(address(this), $(mgv), 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockPartialFillBuyOrder({
      takerWants: ask.gives() / 2,
      tick: ask.tick(),
      partialFill: 1,
      _olBaseQuote: olKey,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 6);
    order.offer = ask;
    // making mgv mappings hot
    mgv.config(olKey);
    mgv.config(lo);

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
