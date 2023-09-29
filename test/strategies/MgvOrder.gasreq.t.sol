// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "mgv_strat_test/lib/StratTest.sol";
import {TestTaker} from "mgv_test/lib/agents/TestTaker.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MangroveOrder} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {IOrderLogic} from "mgv_strat_src/strategies/interfaces/IOrderLogic.sol";
import {IERC20, OLKey, Offer} from "mgv_src/MgvLib.sol";
import {TickLib} from "mgv_lib/TickLib.sol";
import {MAX_TICK} from "mgv_lib/Constants.sol";
import {Tick} from "mgv_lib/TickLib.sol";
import {OfferGasReqBaseTest} from "mgv_test/lib/gas/OfferGasReqBase.t.sol";
import {OfferGasBaseBaseTest} from "mgv_test/lib/gas/OfferGasBaseBase.t.sol";

///@notice Can be used to test gasreq for MangroveOrder. Pick the highest value reported by -vv and subtract gasbase.
///@dev Remember to use same optimization options for core and strats when comparing.
abstract contract MangroveOrderGasreqBaseTest is StratTest, OfferGasReqBaseTest {
  MangroveOrder internal mangroveOrder;
  IOrderLogic.TakerOrderResult internal buyResult;
  IOrderLogic.TakerOrderResult internal sellResult;
  TestTaker internal takerOl;
  TestTaker internal takerLo;

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual override {
    super.setUpTokens(baseToken, quoteToken);
    mangroveOrder = new MangroveOrder(IMangrove(payable(mgv)), $(this), 400_000);
    mangroveOrder.activate(dynamic([IERC20(base), IERC20(quote)]));

    // We approve both base and quote to be able to test both tokens.
    // We should approve 2*volume but do not in order to allow failure to deliver
    deal($(quote), $(this), 10 ether);
    TransferLib.approveToken(quote, $(mangroveOrder.router()), 1.5 ether);

    deal($(base), $(this), 10 ether);
    TransferLib.approveToken(base, $(mangroveOrder.router()), 1.5 ether);

    // A buy
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      olKey: olKey,
      fillOrKill: false,
      fillWants: false,
      fillVolume: 1 ether,
      tick: Tick.wrap(10),
      restingOrder: true,
      expiryDate: block.timestamp + 10000,
      offerId: 0
    });

    // Post everything as resting order since offer list is empty with plenty of provision
    buyResult = mangroveOrder.take{value: 1 ether}(buyOrder);

    assertGt(buyResult.offerId, 0, "Resting offer failed to be published on mangrove");

    // A sell
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      olKey: lo,
      fillOrKill: false,
      fillWants: false,
      fillVolume: 1 ether,
      tick: Tick.wrap(-20),
      restingOrder: true,
      expiryDate: block.timestamp + 10000,
      offerId: 0
    });

    // Post everything as resting order since offer list is empty with plenty of provision
    sellResult = mangroveOrder.take{value: 1 ether}(sellOrder);

    assertGt(sellResult.offerId, 0, "Resting offer failed to be published on mangrove");

    // Create taker for taking the buy offer
    takerLo = setupTaker(lo, "Taker");
    takerLo.approveMgv(base, type(uint).max);
    deal($(base), $(takerLo), 10 ether);

    // Create taker for taking the sell offer
    takerOl = setupTaker(olKey, "Taker");
    takerOl.approveMgv(quote, type(uint).max);
    deal($(quote), $(takerOl), 10 ether);

    description = string.concat(description, " - MangroveOrder");
  }

  function test_gasreq_repost_on_now_empty_offer_list_with_expiry(OLKey memory _olKey, TestTaker taker, bool failure)
    internal
  {
    // note: we do not test failure in posthook as it is not supposed to fail for MangroveOrder.
    // we take more than approval to make makerExecute fail
    // this is more expensive than expiry which fails earlier.
    uint volume = failure ? type(uint96).max : 1;

    (IMangrove _mgv,,,) = getStored();
    vm.prank($(taker));
    _gas();
    (uint takerGot,, uint bounty,) = _mgv.marketOrderByTick(_olKey, Tick.wrap(MAX_TICK), volume, true);
    gas_();
    assertEq(takerGot == 0, failure, "taker should get some of the offer if not failure");
    assertEq(mgv.best(_olKey), failure ? 0 : buyResult.offerId, "offer should be reposted if not failure");
    assertEq(bounty != 0, failure, "bounty should be paid for failure");
  }

  function test_gasreq_repost_on_now_empty_offer_list_with_expiry_base_quote_success() public {
    test_gasreq_repost_on_now_empty_offer_list_with_expiry(olKey, takerOl, false);
    description =
      string.concat(description, " - Case: base/quote gasreq for taking single offer and repost to now empty book");
    printDescription();
  }

  function test_gasreq_repost_on_now_empty_offer_list_with_expiry_quote_base_success() public {
    test_gasreq_repost_on_now_empty_offer_list_with_expiry(lo, takerLo, false);
    description =
      string.concat(description, " - Case: quote/base gasreq for taking single offer and repost to now empty book");
    printDescription();
  }

  function test_gasreq_repost_on_now_empty_offer_list_with_expiry_base_quote_failure() public {
    test_gasreq_repost_on_now_empty_offer_list_with_expiry(olKey, takerOl, true);
    description = string.concat(
      description, " - Case: base/quote gasreq for taking single failing offer on now empty book so not reposted"
    );
    printDescription();
  }

  function test_gasreq_repost_on_now_empty_offer_list_with_expiry_quote_base_failure() public {
    test_gasreq_repost_on_now_empty_offer_list_with_expiry(lo, takerLo, true);
    description = string.concat(
      description, " - Case: quote/base gasreq for taking single failing offer on now empty book so not reposted"
    );
    printDescription();
  }
}

contract MangroveOrderGasreqTest_Generic_A_B is MangroveOrderGasreqBaseTest {
  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}

contract MangroveOrderGasreqTest_Polygon_WETH_DAI is MangroveOrderGasreqBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}

///@notice For comparison to subtract from results of the above.
contract OfferGasBaseTest_Polygon_WETH_DAI is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}
