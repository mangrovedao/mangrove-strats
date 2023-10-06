// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "mgv_strat_test/lib/StratTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {OLKey, Offer} from "mgv_src/core/MgvLib.sol";
import {TickLib} from "mgv_lib/core/TickLib.sol";
import {MAX_TICK} from "mgv_lib/core/Constants.sol";
import {Tick} from "mgv_lib/core/TickLib.sol";
import {OfferGasReqBaseTest} from "mgv_test/lib/gas/OfferGasReqBase.t.sol";
import {Kandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {AavePooledRouter} from "mgv_strat_src/strategies/routers/integrations/AavePooledRouter.sol";
import {AaveKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";

///@notice Can be used to test gasreq for Kandel. Pick the highest value reported by -vv and subtract gasbase.
///@dev Remember to use same optimization options for core and strats when comparing.
abstract contract CoreKandelGasreqBaseTest is StratTest, OfferGasReqBaseTest {
  GeometricKandel internal kandel;

  event LogIncident(bytes32 indexed olKeyHash, uint indexed offerId, bytes32 makerData, bytes32 mgvData);

  bytes32 internal expectedFirOfferMakerData = 0;

  function printDescription(string memory postfix) public virtual {
    description = string.concat(description, postfix);
    printDescription();
  }

  function createKandel() public virtual returns (GeometricKandel);

  function populateKandel() public virtual {
    deal($(this), 10 ether);
    TransferLib.approveToken(base, address(kandel), type(uint).max);
    TransferLib.approveToken(quote, address(kandel), type(uint).max);
    deal($(quote), $(this), 10 ether);
    deal($(base), $(this), 10 ether);

    GeometricKandel.Params memory params;
    params.stepSize = 1;
    params.pricePoints = 2;
    kandel.populateFromOffset{value: 1 ether}({
      from: 0,
      to: params.pricePoints,
      baseQuoteTickIndex0: Tick.wrap(1),
      _baseQuoteTickOffset: 1,
      firstAskIndex: 1,
      bidGives: 1 ether,
      askGives: 1 ether,
      parameters: params,
      baseAmount: 2 ether,
      quoteAmount: 2 ether
    });

    // Make dual live
    TransferLib.approveToken(base, address(mgv), type(uint).max);
    TransferLib.approveToken(quote, address(mgv), type(uint).max);
    mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), 0.5 ether, true);
  }

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual override {
    super.setUpTokens(baseToken, quoteToken);

    kandel = createKandel();
    populateKandel();
  }

  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(
    OLKey memory _olKey,
    bool failure,
    uint volume,
    bool expectRepostSelf,
    bool expectLiveDual
  ) internal {
    if (failure) {
      vm.prank(address(kandel));
      TransferLib.approveToken(base, $(mgv), 0);
      TransferLib.approveToken(quote, $(mgv), 0);
    }

    (IMangrove _mgv,,,) = getStored();
    prankTaker(_olKey);
    _gas();
    (uint takerGot,, uint bounty,) = _mgv.marketOrderByTick(_olKey, Tick.wrap(MAX_TICK), volume, true);
    gas_();
    assertEq(takerGot == 0, failure, "taker should get some of the offer if not failure");
    if (expectRepostSelf) {
      assertGt(mgv.best(_olKey), 0, "offer should be reposted");
    } else {
      assertEq(mgv.best(_olKey), 0, "offer should not be reposted");
    }
    if (expectLiveDual) {
      assertGt(mgv.best(_olKey.flipped()), 0, "dual offer should be live");
    } else {
      assertEq(mgv.best(_olKey.flipped()), 0, "dual offer should not be live");
    }
    assertEq(bounty != 0, failure, "bounty should be paid for failure");
  }

  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_base_quote_repost_both() public {
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(olKey, false, 0.25 ether, true, true);
    printDescription(" - Case: base/quote gasreq for taking offer repost self and dual to now empty book");
  }

  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_quote_base_repost_both() public {
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(lo, false, 0.25 ether, true, true);
    printDescription(" - Case: quote/base gasreq for taking offer repost self and dual to now empty book");
  }

  // Compare this to the non-setGasprice version to see the delta caused by hot hotness. This should be then added to tests that need to set gasprice to change scenario.
  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_base_quote_repost_both_setGasprice()
    public
  {
    mgv.setGasprice(1);
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(olKey, false, 0.25 ether, true, true);
    printDescription(
      " - Case: base/quote gasreq for taking offer repost self and dual to now empty book + setGasPrice prior"
    );
  }

  // Compare this to the non-setAllowances version to see the delta caused by hotness. This should be then added to tests that need to set allowances to change scenario.
  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_base_quote_repost_both_setAllowances()
    public
  {
    vm.prank(address(kandel));
    TransferLib.approveToken(base, address(mgv), type(uint).max - 42);
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(olKey, false, 0.25 ether, true, true);
    printDescription(
      " - Case: base/quote gasreq for taking offer repost self and dual to now empty book + set allowance prior"
    );
  }

  // Compare this to the non-setAllowances version to see the delta caused by hotness. This should be then added to tests that need to set allowances to change scenario.
  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_quote_base_repost_both_setAllowances()
    public
  {
    vm.prank(address(kandel));
    TransferLib.approveToken(quote, address(mgv), type(uint).max - 42);
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(lo, false, 0.25 ether, true, true);
    printDescription(
      " - Case: quote/base gasreq for taking offer repost self and dual to now empty book + set allowance prior"
    );
  }

  ///@notice fail to repost and update due to high gasprice, remember to add delta for hotness of gasprice. Note: Dual keeps being live as update fails it keeps old values.
  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_base_quote_repost_both_fails_due_to_gasprice(
  ) public {
    mgv.setGasprice(2 ** 26 - 1);
    expectFrom(address(kandel));
    emit LogIncident(lo.hash(), 1, "Kandel/updateOfferFailed", "mgv/insufficientProvision");
    expectFrom(address(kandel));
    emit LogIncident(olKey.hash(), 1, expectedFirOfferMakerData, "mgv/insufficientProvision");
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(olKey, false, 0.25 ether, false, true);
    printDescription(
      " - Case: base/quote gasreq for taking offer which fails repost self and dual to now empty book due to gasprice"
    );
  }

  ///@notice fail to repost and update due to high gasprice, remember to add delta for hotness of gasprice. Note: Dual keeps being live as update fails it keeps old values.
  function test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list_quote_base_repost_both_fails_due_to_gasprice(
  ) public {
    mgv.setGasprice(2 ** 26 - 1);
    expectFrom(address(kandel));
    emit LogIncident(olKey.hash(), 1, "Kandel/updateOfferFailed", "mgv/insufficientProvision");
    expectFrom(address(kandel));
    emit LogIncident(lo.hash(), 1, expectedFirOfferMakerData, "mgv/insufficientProvision");
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(lo, false, 0.25 ether, false, true);
    printDescription(
      " - Case: quote/base gasreq for taking offer which fails repost self and dual to now empty book due to gasprice"
    );
  }

  ///@notice fail to deliver (and therefore fail to repost and post dual) due to missing allowance, remember to add delta for hotness of allowance.
  function test_gasreq_delivery_failure_due_to_allowance_base_quote() public {
    vm.prank(address(kandel));
    TransferLib.approveToken(base, address(mgv), 0);
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(olKey, true, 0.25 ether, false, true);
    printDescription(
      " - Case: base/quote gasreq for taking offer which fails to deliver and thus repost, leaves dual as is"
    );
  }

  ///@notice fail to deliver (and therefore fail to repost and post dual) due to missing allowance, remember to add delta for hotness of allowance.
  function test_gasreq_delivery_failure_due_to_allowance_quote_base() public {
    vm.prank(address(kandel));
    TransferLib.approveToken(quote, address(mgv), 0);
    test_gasreq_repost_and_post_dual_first_offer_now_empty_offer_list(lo, true, 0.25 ether, false, true);
    printDescription(
      " - Case: quote/base gasreq for taking offer which fails to deliver and thus repost, leaves dual as is"
    );
  }

  // self or dual below density.

  //TODO test where dual is retracted to verify it is not more expensive.
  // dead dual, repost self, and make dual live
  // dead dual, repost self, but self and dual below density
}

abstract contract NoRouterKandelGasreqBaseTest is CoreKandelGasreqBaseTest {
  function createKandel() public virtual override returns (GeometricKandel) {
    description = string.concat(description, " - Kandel");
    return new Kandel({
        mgv: mgv,
        olKeyBaseQuote: olKey,
        gasreq: 500_000,
        reserveId: address(0)
      });
  }
}

abstract contract AaveKandelGasreqBaseTest is CoreKandelGasreqBaseTest {
  function createKandel() public virtual override returns (GeometricKandel) {
    description = string.concat(description, " - AaveKandel");
    expectedFirOfferMakerData = "IS_FIRST_PULLER";

    address aave = fork.get("Aave");
    AavePooledRouter router = new AavePooledRouter(aave, 500_000);
    AaveKandel aaveKandel = new AaveKandel({
      mgv: mgv,
      olKeyBaseQuote: olKey,
      gasreq: 500_000,
      reserveId: $(this)
    });

    router.bind(address(aaveKandel));
    aaveKandel.initialize(router);

    return aaveKandel;
  }
}

contract NoRouterKandelGasreqBaseTest_Generic_A_B is NoRouterKandelGasreqBaseTest {
  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}

contract NoRouterKandelGasreqBaseTest_Polygon_WETH_DAI is NoRouterKandelGasreqBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}

contract AaveKandelGasreqBaseTest_Polygon_WETH_DAI is AaveKandelGasreqBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}
