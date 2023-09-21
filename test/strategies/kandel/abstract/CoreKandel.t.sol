// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./KandelTest.t.sol";
import {MAX_LOG_PRICE, MIN_LOG_PRICE, MAX_SAFE_VOLUME} from "mgv_lib/Constants.sol";

abstract contract CoreKandelTest is KandelTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function test_init() public {
    assertApproxEqAbs(kdl.pending(Ask), 0, 1, "Incorrect initial pending (can be off by 1 due to rounding for Aave)");
    assertApproxEqAbs(kdl.pending(Bid), 0, 1, "Incorrect initial pending (can be off by 1 due to rounding for Aave)");
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_bid_complete_fill() public {
    test_bid_complete_fill(3);
  }

  function test_bid_complete_fill(uint index) internal {
    vm.prank(maker);

    MgvStructs.OfferPacked oldAsk = kdl.getOffer(Ask, index + STEP);
    int oldPending = kdl.pending(Ask);

    (uint takerGot, uint takerGave,, uint fee) = sellToBestAs(taker, 1000 ether);
    assertTrue(takerGot > 0, "Take failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newAsk = kdl.getOffer(Ask, index + STEP);
    assertTrue(newAsk.gives() <= takerGave + oldAsk.gives(), "Cannot give more than what was received");
    int pendingDelta = kdl.pending(Ask) - oldPending;
    // Allow a discrepancy of 1 for aave router shares
    assertApproxEqAbs(
      pendingDelta + int(newAsk.gives()),
      int(oldAsk.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );

    assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "There should be no pending since we compound all returns");
    assertTrue(newAsk.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
  }

  function test_ask_complete_fill() public {
    test_ask_complete_fill(5);
  }

  function test_ask_complete_fill(uint index) internal {
    MgvStructs.OfferPacked oldBid = kdl.getOffer(Bid, index - STEP);
    int oldPending = kdl.pending(Bid);

    (uint takerGot, uint takerGave,, uint fee) = buyFromBestAs(taker, 1000 ether);
    assertTrue(takerGot > 0, "buy failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newBid = kdl.getOffer(Bid, index - STEP);
    assertTrue(newBid.gives() <= takerGave + oldBid.gives(), "Cannot give more than what was received");
    int pendingDelta = kdl.pending(Bid) - oldPending;
    assertApproxEqAbs(
      pendingDelta + int(newBid.gives()),
      int(oldBid.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );

    assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "We do full compounding so there should be no pending");
    assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
  }

  function test_bid_partial_fill() public {
    (uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(takerGot > 0, "order failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 2, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill() public {
    (uint takerGot,,,) = buyFromBestAs(taker, 0.01 ether);
    assertTrue(takerGot > 0, "order failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill_existingDual() public {
    partial_fill(Ask, true);
  }

  function test_bid_partial_fill_existingDual() public {
    partial_fill(Bid, true);
  }

  function test_ask_partial_fill_noDual() public {
    partial_fill(Ask, false);
  }

  function test_bid_partial_fill_noDual() public {
    partial_fill(Bid, false);
  }

  function testFail_ask_partial_fill_noDual_noIncident() public {
    vm.expectEmit(false, false, false, false, $(kdl));
    emit LogIncident(olKey.hash(), 0, "", "");
    partial_fill(Ask, false);
  }

  function partial_fill(OfferType ba, bool existingDual) internal {
    // Arrange
    uint takerGot;
    if (existingDual) {
      // Create dual by taking a small amount of the best bid (big enough so dual is created)
      (takerGot,,,) = sellToBestAs(taker, 0.01 ether);
      assertTrue(takerGot > 0, "take to create dual failed");
      assertStatus(dynamic([uint(1), 1, 1, 1, 2, 2, 2, 2, 2, 2]));
    } else {
      assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
    }

    // Act
    (takerGot,,,) = ba == Ask ? buyFromBestAs(taker, 1 wei) : sellToBestAs(taker, 1 wei);

    // Assert
    if (ba == Ask) {
      // taker gets nothing for Bid due to sending so little and rounding
      assertTrue(takerGot > 0, "Taker did not get expected");
    }
    if (existingDual) {
      // a tiny bit ends up as pending - but all offers still live
      assertStatus(dynamic([uint(1), 1, 1, 1, 2, 2, 2, 2, 2, 2]));
    } else {
      // the dual offer could not be made live due to too little transported - but residual still reposted
      if (ba == Ask) {
        assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      } else {
        assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      }
    }
  }

  function test_all_bids_all_asks_and_back() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
    vm.prank(taker);
    mgv.marketOrderByVolume(olKey, type(uint96).max, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]));
    vm.prank(taker);
    mgv.marketOrderByVolume(lo, 1 ether, type(uint96).max, false);
    assertStatus(dynamic([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]));
    uint askVol = kdl.offeredVolume(Ask);
    vm.prank(taker);
    mgv.marketOrderByVolume(olKey, askVol / 2, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_take_new_offer() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    assertStatus(dynamic([uint(1), 1, 0, 2, 2, 2, 2, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]));
  }

  function test_retractOffers() public {
    uint preBalance = maker.balance;
    uint preMgvBalance = mgv.balanceOf(address(kdl));

    expectFrom($(kdl));
    emit RetractStart();
    expectFrom($(mgv));
    emit OfferRetract(lo.hash(), $(kdl), kdl.offerIdOfIndex(Bid, 0), true);
    expectFrom($(kdl));
    emit RetractEnd();

    vm.prank(maker);
    kdl.retractOffers(0, 5);
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    assertEq(0, kdl.offeredVolume(Ask), "All ask volume should be retracted");
    assertEq(0, kdl.offeredVolume(Bid), "All bid volume should be retracted");
    assertGt(mgv.balanceOf(address(kdl)), preMgvBalance, "Kandel should have balance on mgv after retract");
    assertEq(maker.balance, preBalance, "maker should not be credited yet");

    vm.prank(maker);
    kdl.withdrawFromMangrove(type(uint).max, maker);
    assertGt(maker.balance, preBalance, "maker should be credited");
  }

  function test_take_full_bid_and_ask_repeatedly(
    uint loops,
    ExpectedChange baseVolumeChange,
    ExpectedChange quoteVolumeChange
  ) internal {
    deal($(base), taker, cash(base, 5000));
    deal($(quote), taker, cash(quote, 7000000));
    uint initialTotalVolumeBase;
    uint initialTotalVolumeQuote;
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
    for (uint i = 0; i < loops; i++) {
      test_ask_complete_fill(5);
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      if (i == 0) {
        // With the ask filled, what is the current volume for bids?
        initialTotalVolumeQuote = kdl.offeredVolume(Bid);
        console.log("Initial bids");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(quoteVolumeChange, initialTotalVolumeQuote, kdl.offeredVolume(Bid), "quote volume");
        console.log("Final bids");
        printOB();
      }
      console.log("loop %s", i);
      test_bid_complete_fill(4);

      assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      if (i == 0) {
        // With the bid filled, what is the current volume for asks?
        initialTotalVolumeBase = kdl.offeredVolume(Ask);
        console.log("Initial asks");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(baseVolumeChange, initialTotalVolumeBase, kdl.offeredVolume(Ask), "base volume");
        console.log("Final asks");
        printOB();
      }
    }
  }

  function test_take_full_bid_and_ask_10_times() public {
    test_take_full_bid_and_ask_repeatedly(10, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function retractDefaultSetup() internal {
    uint baseFunds = kdl.offeredVolume(Ask) + uint(kdl.pending(Ask));
    uint quoteFunds = kdl.offeredVolume(Bid) + uint(kdl.pending(Bid));
    vm.prank(maker);
    kdl.retractAndWithdraw(0, 10, baseFunds, quoteFunds, type(uint).max, maker);
  }

  function test_reserveBalance_withoutOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function test_reserveBalance_withOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    populateConstantDistribution(4);

    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function test_offeredVolume_withOffers_returnsSumOfGives() public {
    // Arrange
    retractDefaultSetup();

    (uint baseAmount, uint quoteAmount) = populateConstantDistribution(4);

    // Act/assert
    assertEq(kdl.offeredVolume(Bid), quoteAmount, "Bid volume should be sum of quote dist");
    assertEq(kdl.offeredVolume(Ask), baseAmount, "Ask volume should be sum of base dist");
  }

  function test_pending_withoutOffers_returnsReserveBalance() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.pending(Ask), 0, "Base pending should be empty");
    assertEq(kdl.pending(Bid), 0, "Quote pending should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.pending(Ask), 42, "Base pending should be correct");
    assertEq(kdl.pending(Bid), 43, "Quote pending should be correct");
  }

  function test_pending_withOffers_disregardsOfferedVolume() public {
    // Arrange
    retractDefaultSetup();
    (uint baseAmount, uint quoteAmount) = populateConstantDistribution(4);

    assertEq(-kdl.pending(Ask), int(baseAmount), "Base pending should be correct");
    assertEq(-kdl.pending(Bid), int(quoteAmount), "Quote pending should be correct");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    assertEq(-kdl.pending(Ask), int(baseAmount - 42), "Base pending should be correct");
    assertEq(-kdl.pending(Bid), int(quoteAmount - 43), "Quote pending should be correct");
  }

  function test_populate_allBids_successful() public {
    test_populate_allBidsAsks_successful(true);
  }

  function test_populate_allAsks_successful() public {
    test_populate_allBidsAsks_successful(false);
  }

  function test_populate_allBidsAsks_successful(bool bids) internal {
    retractDefaultSetup();

    CoreKandel.Distribution memory emptyDistribution;
    CoreKandel.Distribution memory distribution;
    distribution.indices = dynamic([uint(0), 1, 2, 3]);
    distribution.logPriceDist = dynamic([int(0), 0, 0, 0]);
    distribution.givesDist = dynamic([uint(1 ether), 1 ether, 1 ether, 1 ether]);

    vm.prank(maker);
    mgv.fund{value: maker.balance}($(kdl));
    vm.prank(maker);
    kdl.populateChunk(bids ? distribution : emptyDistribution, bids ? emptyDistribution : distribution);

    uint status = bids ? uint(OfferStatus.Bid) : uint(OfferStatus.Ask);
    assertStatus(dynamic([status, status, status, status]), type(uint).max, type(uint).max);
  }

  function heal(uint midWants, uint midGives, uint densityBid, uint densityAsk) internal {
    // user can adjust pending by withdrawFunds or transferring to Kandel, then invoke heal.
    // heal fills up offers to some designated volume starting from mid-price.
    // Designated volume should either be equally divided between holes, or be based on Kandel Density
    // Here we assume its some constant.
    // Note this example implementation! It does not cover all corner cases.
    // * does not support no bids
    // * uses initQuote/initBase as starting point - not available on-chain
    // * assumes mid-price and bid/asks on the book are not crossed.

    uint baseDensity = densityBid;
    uint quoteDensity = densityAsk;

    CoreKandel.Distribution memory bidDistribution;
    CoreKandel.Distribution memory askDistribution;

    (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids) = getDeadOffers(midGives, midWants);
    uint numAsks = indices.length - numBids;

    // build arrays for populate
    bidDistribution.logPriceDist = new int[](numBids);
    bidDistribution.givesDist = new uint[](numBids);
    bidDistribution.indices = new uint[](numBids);
    askDistribution.logPriceDist = new int[](numAsks);
    askDistribution.givesDist = new uint[](numAsks);
    askDistribution.indices = new uint[](numAsks);

    uint pendingQuote = uint(kdl.pending(Bid));
    uint pendingBase = uint(kdl.pending(Ask));

    if (numBids > 0 && baseDensity * numBids < pendingQuote) {
      baseDensity = pendingQuote / numBids; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (int i = int(numBids) - 1; i >= 0; i--) {
      uint d = pendingQuote < baseDensity ? pendingQuote : baseDensity;
      pendingQuote -= d;
      bidDistribution.indices[uint(i)] = indices[uint(i)];
      bidDistribution.givesDist[uint(i)] = d;
      bidDistribution.logPriceDist[uint(i)] =
        LogPriceConversionLib.logPriceFromVolumes(initBase, quoteAtIndex[indices[uint(i)]]);
    }

    if (numAsks > 0 && quoteDensity * numAsks < pendingBase) {
      quoteDensity = pendingBase / numAsks; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (uint i = 0; i < numAsks; i++) {
      uint d = pendingBase < quoteDensity ? pendingBase : quoteDensity;
      pendingBase -= d;
      askDistribution.indices[i] = indices[i + numBids];
      askDistribution.givesDist[i] = d;
      askDistribution.logPriceDist[i] =
        LogPriceConversionLib.logPriceFromVolumes(quoteAtIndex[indices[i + numBids]], initBase);
    }

    GeometricKandel.Params memory params = getParams(kdl);
    vm.prank(maker);
    // Fund mangrove
    kdl.populate{value: 1 ether}(emptyDist(), emptyDist(), params, 0, 0);
    vm.prank(maker);
    kdl.populateChunk(bidDistribution, askDistribution);
  }

  function test_heal_someFailedOffers_reposts(OfferType ba, uint failures, uint[] memory expectedMidStatus) internal {
    // Arrange
    (uint midWants, uint midGives) = getMidPrice();
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();
    uint densityMidBid = bestBid.gives();
    uint densityMidAsk = bestAsk.gives();
    IERC20 outbound = ba == OfferType.Ask ? base : quote;

    // Fail some offers - make offers fail by removing approval
    vm.prank(maker);
    kdl.approve(outbound, $(mgv), 0);
    for (uint i = 0; i < failures; i++) {
      // This will emit LogIncident and OfferFail
      (uint successes,) = ba == Ask ? cleanBuyBestAs(taker, 1 ether) : cleanSellBestAs(taker, 1 ether);
      assertTrue(successes == 1, "Clean should clean");
    }

    // verify offers have gone
    assertStatus(expectedMidStatus);

    // reduce pending volume to let heal only use some of the original volume when healing
    uint halfPending = uint(kdl.pending(ba)) / 2;
    vm.prank(maker);
    uint baseAmount = ba == Ask ? halfPending : 0;
    uint quoteAmount = ba == Ask ? 0 : halfPending;
    kdl.withdrawFunds(baseAmount, quoteAmount, maker);

    // Act
    heal(midWants, midGives, densityMidBid / 2, densityMidAsk / 2);

    // Assert - verify status and prices
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_heal_1FailedAsk_reposts() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
    test_heal_someFailedOffers_reposts(Ask, 1, dynamic([uint(1), 1, 1, 1, 0, 0, 2, 2, 2, 2]));
  }

  function test_heal_1FailedBid_reposts() public {
    test_heal_someFailedOffers_reposts(Bid, 1, dynamic([uint(1), 1, 1, 0, 0, 2, 2, 2, 2, 2]));
  }

  function test_heal_3FailedAsk_reposts() public {
    test_heal_someFailedOffers_reposts(Ask, 3, dynamic([uint(1), 1, 1, 1, 0, 0, 0, 0, 2, 2]));
  }

  function test_heal_3FailedBid_reposts() public {
    test_heal_someFailedOffers_reposts(Bid, 3, dynamic([uint(1), 0, 0, 0, 0, 2, 2, 2, 2, 2]));
  }

  function test_populateChunk_invalidArrayLength_reverts() public {
    CoreKandel.Distribution memory dist;

    // base
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.logPriceDist = new int[](0);
    dist.givesDist = new uint[](1);
    dist.givesDist[0] = 1;
    kdl.populateChunk(emptyDist(), dist);

    // quote
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.logPriceDist = new int[](1);
    dist.givesDist = new uint[](0);
    dist.logPriceDist[0] = 1;
    kdl.populateChunk(dist, emptyDist());
  }

  function test_populate_retracts_at_zero() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);

    populateSingle(kdl, index, 0, 0, 5, bytes(""));
    // Bid should be retracted
    assertStatus(index, OfferStatus.Dead);
  }

  function test_populate_density_too_low_reverted() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    populateSingle(kdl, index, 1, 123, 5, "mgv/writeOffer/density/tooLow");
  }

  function test_populate_existing_offer_is_updated() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    uint offerId = kdl.offerIdOfIndex(Bid, index);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);

    populateSingle(kdl, index, bid.wants() * 2, bid.gives() * 2, 5, "");

    uint offerIdPost = kdl.offerIdOfIndex(Bid, index);
    assertEq(offerIdPost, offerId, "offerId should be unchanged (offer updated)");
    MgvStructs.OfferPacked bidPost = kdl.getOffer(Bid, index);
    assertEq(bidPost.gives(), bid.gives() * 2, "gives should be changed");
  }

  function test_step_higher_than_kandel_size_jumps_to_last() public {
    uint n = getParams(kdl).pricePoints;
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, n - 1);
    // placing a bid on the last position
    // dual of this bid will try to place an ask at n+1 and should place it at n-1 instead of n
    populateSingle(kdl, n - 1, ask.gives(), ask.wants(), n, "");
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, n - 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockPartialFillSellOrder({
      takerWants: bid.gives(),
      logPrice: bid.logPrice(),
      partialFill: 1,
      _olBaseQuote: olKey,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Bid, n - 1);
    order.offer = bid;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked ask_ = kdl.getOffer(Ask, n - 1);

    assertTrue(ask.gives() < ask_.gives(), "Ask was not updated");
    assertApproxEqRel(ask.gives() * ask_.wants(), ask.wants() * ask_.gives(), 1e14, "Incorrect price");
  }

  function test_transport_below_min_price_accumulates_at_index_0() public {
    uint24 logPriceOffset = 769; // corresponding to roughly to 107.992%
    uint firstAskIndex = 5;

    // setting params.stepSize to 4
    GeometricKandel.Params memory params = getParams(kdl);
    params.stepSize = 4;

    int baseQuoteLogPriceIndex0 = LogPriceConversionLib.logPriceFromVolumes(initQuote, initBase);
    (CoreKandel.Distribution memory bidDistribution1, CoreKandel.Distribution memory askDistribution1) = kdl
      .createDistribution(
      0,
      5,
      baseQuoteLogPriceIndex0,
      logPriceOffset,
      firstAskIndex,
      type(uint).max,
      initBase,
      params.pricePoints,
      params.stepSize
    );
    (CoreKandel.Distribution memory bidDistribution2, CoreKandel.Distribution memory askDistribution2) = kdl
      .createDistribution(
      5,
      10,
      baseQuoteLogPriceIndex0,
      logPriceOffset,
      firstAskIndex,
      type(uint).max,
      initBase,
      params.pricePoints,
      params.stepSize
    );

    // repopulating to update the stepSize (but with the same distribution)
    vm.prank(maker);
    kdl.populate{value: 1 ether}(bidDistribution1, askDistribution1, params, 0, 0);
    vm.prank(maker);
    kdl.populateChunk(bidDistribution2, askDistribution2);
    // placing an ask at index 1
    // dual of this ask will try to place a bid at -1 and should place it at 0
    populateSingle(kdl, 1, 0.1 ether, 100 * 10 ** 6, 0, "");

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockPartialFillBuyOrder({
      takerWants: ask.gives(),
      logPrice: ask.logPrice(),
      partialFill: 1,
      _olBaseQuote: olKey,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 1);
    order.offer = ask;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked bid_ = kdl.getOffer(Bid, 0);
    assertTrue(bid.gives() < bid_.gives(), "Bid was not updated");
  }

  function test_fail_to_update_dual_offer_logs_incident() public {
    // closing bid market
    vm.prank(mgv.governance());
    mgv.deactivate(olKey);
    // taking a bid that already has a dual ask
    uint offerId = kdl.offerIdOfIndex(Bid, 4);
    uint offerId_ = kdl.offerIdOfIndex(Ask, 5);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockPartialFillSellOrder({
      takerWants: bid.gives(),
      logPrice: bid.logPrice(),
      partialFill: 1,
      _olBaseQuote: olKey,
      makerData: ""
    });

    order.offerId = offerId;
    order.offer = bid;

    expectFrom($(kdl));
    emit LogIncident(olKey.hash(), offerId_, "Kandel/updateOfferFailed", "mgv/inactive");
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
  }

  function test_posthook_density_too_low_still_posts_to_dual() public {
    uint index = 3;

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    // Take almost all - offer will not be reposted due to density too low
    uint amount = bid.wants() - 1;
    vm.prank(taker);
    mgv.marketOrderByVolume(lo, 0, amount, false);

    // verify dual is increased
    MgvStructs.OfferPacked askPost = kdl.getOffer(Ask, index + STEP);
    assertGt(askPost.gives(), ask.gives(), "Dual should offer more even though bid failed to post");
  }

  function test_posthook_dual_density_too_low_not_posted_via_updateOffer() public {
    // make previous live ask dead
    buyFromBestAs(taker, 1000 ether);

    uint index = 4;

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    assertTrue(bid.isLive(), "bid should be live");
    assertTrue(!ask.isLive(), "ask should not be live");

    // Take very little and expect dual posting to fail.
    uint amount = 10000;
    vm.prank(taker);
    mgv.marketOrderByVolume(lo, 0, amount, false);

    ask = kdl.getOffer(Ask, index + STEP);
    assertTrue(!ask.isLive(), "ask should still not be live");
  }

  uint[] empty = new uint[](0);

  function test_populate_can_get_set_params_keeps_offers() public {
    GeometricKandel.Params memory params = getParams(kdl);

    uint offeredVolumeBase = kdl.offeredVolume(Ask);
    uint offeredVolumeQuote = kdl.offeredVolume(Bid);

    GeometricKandel.Params memory paramsNew;
    paramsNew.pricePoints = params.pricePoints;
    paramsNew.stepSize = params.stepSize + 1;
    paramsNew.gasprice = params.gasprice + 1;
    paramsNew.gasreq = params.gasreq + 1;

    expectFrom(address(kdl));
    emit SetStepSize(paramsNew.stepSize);
    expectFrom(address(kdl));
    emit SetGasprice(paramsNew.gasprice);
    expectFrom(address(kdl));
    emit SetGasreq(paramsNew.gasreq);

    vm.prank(maker);
    kdl.populate(emptyDist(), emptyDist(), paramsNew, 0, 0);

    GeometricKandel.Params memory params_ = getParams(kdl);

    assertEq(params_.gasprice, paramsNew.gasprice, "gasprice should be changed");
    assertEq(params_.gasreq, paramsNew.gasreq, "gasreq should be changed");
    assertEq(params_.pricePoints, params.pricePoints, "pricePoints should not be changed");
    assertEq(params_.stepSize, params.stepSize + 1, "stepSize should be changed");
    assertEq(offeredVolumeBase, kdl.offeredVolume(Ask), "ask volume should be unchanged");
    assertEq(offeredVolumeQuote, kdl.offeredVolume(Bid), "ask volume should be unchanged");
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]), type(uint).max, type(uint).max);
  }

  function test_populate_throws_on_invalid_stepSize_low() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.stepSize = 0;
    vm.prank(maker);
    vm.expectRevert("Kandel/stepSizeTooLow");
    kdl.populate(emptyDist(), emptyDist(), params, 0, 0);
  }

  function test_populate_throws_on_invalid_stepSize_high() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/stepSizeTooHigh");
    kdl.setStepSize(2 ** 104);
  }

  function test_populate_throws_on_invalid_stepSize_wrt_pricePoints() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.stepSize = 10;
    vm.prank(maker);
    vm.expectRevert("Kandel/stepSizeTooHigh");
    kdl.populate(emptyDist(), emptyDist(), params, 0, 0);
  }

  function test_populate_throws_on_invalid_pricePoints_low() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 1;
    params.stepSize = 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidPricePoints");
    kdl.populate(emptyDist(), emptyDist(), params, 0, 0);
  }

  function test_populate_throws_on_invalid_pricePoints_high() public {
    GeometricKandel.Params memory params;
    params.pricePoints = uint112(uint(2 ** 112));
    params.stepSize = 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidPricePoints");
    kdl.populate(emptyDist(), emptyDist(), params, 0, 0);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_via_createDistribution() public {
    test_populate_can_repopulate_other_size_and_other_params(false);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_via_populateFromOffset() public {
    test_populate_can_repopulate_other_size_and_other_params(true);
  }

  function test_populate_can_repopulate_other_size_and_other_params(bool viaPopulateFromOFfset) internal {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    logPriceOffset = 200;
    uint firstAskIndex = 3;

    GeometricKandel.Params memory params;
    params.pricePoints = 5;
    params.stepSize = 2;

    int baseQuoteLogPriceIndex0 = LogPriceConversionLib.logPriceFromVolumes(initQuote, initBase);

    if (viaPopulateFromOFfset) {
      expectFrom(address(kdl));
      emit SetLength(params.pricePoints);
      expectFrom(address(kdl));
      emit SetBaseQuoteLogPriceOffset(logPriceOffset);
      vm.prank(maker);
      kdl.populateFromOffset(
        0, 5, baseQuoteLogPriceIndex0, logPriceOffset, firstAskIndex, type(uint).max, initBase, params, 0, 0
      );
    } else {
      (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
        .createDistribution(
        0,
        5,
        baseQuoteLogPriceIndex0,
        logPriceOffset,
        firstAskIndex,
        type(uint).max,
        initBase,
        params.pricePoints,
        params.stepSize
      );

      expectFrom(address(kdl));
      emit SetLength(params.pricePoints);
      vm.prank(maker);
      kdl.populate(bidDistribution, askDistribution, params, 0, 0);
      expectFrom(address(kdl));
      emit SetBaseQuoteLogPriceOffset(logPriceOffset);
      vm.prank(maker);
      kdl.setBaseQuoteLogPriceOffset(logPriceOffset);
    }

    // This verifies stepSize during creation
    assertStatus(dynamic([uint(1), 1, 0, 0, 2]));

    sellToBestAs(taker, 1 ether);

    // This verifies transport uses stepSize
    assertStatus(dynamic([uint(1), 0, 0, 2, 2]));
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(0), 0, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 0, 0, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 0, 0, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 0, 0]));
  }

  function test_populates_emits() public {
    expectFrom($(kdl));
    emit PopulateStart();
    vm.expectEmit(false, false, false, false, $(mgv));
    emit OfferWrite(bytes32(0), address(0), 0, 0, 0, 0, 0);
    expectFrom($(kdl));
    emit PopulateEnd();
    populateSingle(kdl, 1, 1 ether, 1 ether, 2, bytes(""));
  }

  function test_setGasprice_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasprice(42);
    vm.prank(maker);
    kdl.setGasprice(42);
    (uint16 gasprice,,,) = kdl.params();
    assertEq(gasprice, uint16(42), "Incorrect gasprice in params");
  }

  function test_setGasprice_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gaspriceTooHigh");
    kdl.setGasprice(2 ** 16);
  }

  function test_setGasreq_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasreq(42);
    vm.prank(maker);
    kdl.setGasreq(42);
    (, uint24 gasreq,,) = kdl.params();
    assertEq(gasreq, uint24(42), "Incorrect gasprice in params");
  }

  function test_setGasreq_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gasreqTooHigh");
    kdl.setGasreq(2 ** 24);
  }

  function test_retractAndWithdraw() public {
    address payable recipient = freshAddress();
    uint baseBalance = kdl.reserveBalance(Ask);
    uint quoteBalance = kdl.reserveBalance(Bid);
    expectFrom($(kdl));
    emit Debit(base, baseBalance);
    expectFrom($(kdl));
    emit Debit(quote, quoteBalance);
    vm.prank(maker);
    kdl.retractAndWithdraw(0, 10, baseBalance, quoteBalance, type(uint).max, recipient);

    assertEq(quoteBalance, quote.balanceOf(recipient), "quote balance should be sent to recipient");
    assertEq(baseBalance, base.balanceOf(recipient), "quote balance should be sent to recipient");
    assertGt(recipient.balance, 0, "wei should be at recipient");
    assertEq(0, kdl.offeredVolume(Bid), "no bids should be live");
    assertEq(0, kdl.offeredVolume(Ask), "no bids should be live");
  }

  function test_depositFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    TransferLib.approveToken(base, $(kdl), baseAmount);
    TransferLib.approveToken(quote, $(kdl), quoteAmount);

    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    kdl.depositFunds(baseAmount, quoteAmount);

    assertApproxEqRel(baseBalance + baseAmount, kdl.reserveBalance(Ask), 10 ** 10, "Incorrect base deposit");
    assertApproxEqRel(quoteBalance + quoteAmount, kdl.reserveBalance(Bid), 10 ** 10, "Incorrect base deposit");
  }

  function test_deposit0Funds() public {
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);
    kdl.depositFunds(0, 0);
    assertEq(kdl.reserveBalance(Ask), baseBalance, "Incorrect base deposit");
    assertEq(kdl.reserveBalance(Bid), quoteBalance, "Incorrect quote deposit");
  }

  function test_withdrawFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    TransferLib.approveToken(base, $(kdl), baseAmount);
    TransferLib.approveToken(quote, $(kdl), quoteAmount);

    kdl.depositFunds(baseAmount, quoteAmount);

    vm.prank(maker);
    kdl.withdrawFunds(baseAmount, quoteAmount, address(this));
    assertEq(base.balanceOf(address(this)), baseAmount, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteAmount, "Incorrect quote withdrawal");
  }

  function test_withdrawAll() public {
    deal($(base), address(this), 1 ether);
    deal($(quote), address(this), 100 * 10 ** 6);
    TransferLib.approveToken(base, $(kdl), 1 ether);
    TransferLib.approveToken(quote, $(kdl), 100 * 10 ** 6);

    kdl.depositFunds(1 ether, 100 * 10 ** 6);
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    vm.prank(maker);
    kdl.withdrawFunds(type(uint).max, type(uint).max, address(this));
    assertEq(base.balanceOf(address(this)), baseBalance, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteBalance, "Incorrect quote withdrawal");
  }

  function test_marketOrder_dualOfferUpdate_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(false, 87985);
  }

  function test_marketOrder_dualOfferNew_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(true, 0);
  }

  function marketOrder_dualOffer_expectedGasreq(bool dualNew, uint deltaGasForNew) internal {
    // Arrange
    MgvLib.SingleOrder memory order = mockCompleteFillBuyOrder({
      takerWants: 0.1 ether,
      logPrice: LogPriceConversionLib.logPriceFromVolumes(0.1 ether, cash(quote, 100))
    });
    order.offerId = kdl.offerIdOfIndex(Ask, dualNew ? 6 : 5);

    // Act
    vm.prank($(mgv));
    uint gasTemp = gasleft();
    bytes32 makerData = kdl.makerExecute(order);
    uint makerExecuteCost = gasTemp - gasleft();

    assertTrue(makerData == bytes32(0) || makerData == "IS_FIRST_PULLER", "Unexpected returned data");

    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: makerData, mgvData: "mgv/tradeSuccess"});

    vm.prank($(mgv));
    gasTemp = gasleft();
    kdl.makerPosthook(order, result);
    uint posthookCost = gasTemp - gasleft();
    // Assert
    (, MgvStructs.LocalPacked local) = mgv.config(olKey);
    console.log("makerExecute: %d, posthook: %d, deltaGasForNew", makerExecuteCost, posthookCost, deltaGasForNew);
    console.log(
      "Strat gasreq (%d), mockup (%d)",
      kdl.offerGasreq() + local.offer_gasbase(),
      makerExecuteCost + posthookCost + deltaGasForNew
    );
    //assertTrue(makerExecuteCost + posthookCost <= kdl.offerGasreq() + local.offer_gasbase(), "Strat is spending more gas");
  }

  function deployOtherKandel(uint base0, uint quote0, uint24 logPriceOffset, GeometricKandel.Params memory otherParams)
    internal
  {
    address otherMaker = freshAddress();

    GeometricKandel otherKandel = __deployKandel__(otherMaker, otherMaker);

    vm.prank(otherMaker);
    TransferLib.approveToken(base, address(otherKandel), type(uint).max);
    vm.prank(otherMaker);
    TransferLib.approveToken(quote, address(otherKandel), type(uint).max);

    uint totalProvision = (
      reader.getProvision(olKey, otherKandel.offerGasreq(), bufferedGasprice)
        + reader.getProvision(lo, otherKandel.offerGasreq(), bufferedGasprice)
    ) * 10 ether;

    deal(otherMaker, totalProvision);

    CoreKandel.Distribution[] memory distribution = new CoreKandel.Distribution[](2);
    {
      (distribution[0], distribution[1]) = kdl.createDistribution(
        0,
        otherParams.pricePoints,
        LogPriceConversionLib.logPriceFromVolumes(quote0, base0),
        logPriceOffset,
        otherParams.pricePoints / 2,
        type(uint).max,
        base0,
        otherParams.pricePoints,
        otherParams.stepSize
      );
    }

    vm.prank(otherMaker);
    otherKandel.populate{value: totalProvision}(distribution[0], distribution[1], otherParams, 0, 0);

    uint pendingBase = uint(-otherKandel.pending(Ask));
    uint pendingQuote = uint(-otherKandel.pending(Bid));
    deal($(base), otherMaker, pendingBase);
    deal($(quote), otherMaker, pendingQuote);

    vm.prank(otherMaker);
    otherKandel.depositFunds(pendingBase, pendingQuote);
  }

  function test_reverseLogPrice() public {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params = getParams(kdl);

    // reversed price
    int baseQuoteLogPriceIndex0 = LogPriceConversionLib.logPriceFromVolumes(initBase, initQuote);

    vm.prank(maker);
    kdl.populateFromOffset({
      from: 0,
      to: 10,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: 5,
      bidGives: type(uint).max,
      askGives: initQuote,
      parameters: params,
      baseAmount: 0,
      quoteAmount: 0
    });

    // Assert inverse price
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]), initBase, initQuote);
  }

  function test_tickScale100_misaligned_offset_price0() public {
    // A low misalignment gets rounded away so test is simple, larger offsets from tick scale would yield different results.
    test_tickScale100_aligned_offset_price0(1);
  }

  function test_tickScale100_aligned_offset_price0() public {
    test_tickScale100_aligned_offset_price0(0);
  }

  function test_tickScale100_aligned_offset_price0(uint offset) internal {
    options.defaultTickScale = 100;
    logPriceOffset = 700 + offset;
    initBase = LogPriceLib.outboundFromInbound(1000 + int(offset), initQuote);
    setUp();

    assertEq(kdl.TICK_SCALE(), 100);
    uint pricePoints = getParams(kdl).pricePoints;
    for (uint i; i < getParams(kdl).pricePoints; i++) {
      assertEq(
        kdl.getOffer(Ask, i).logPrice(),
        i < STEP ? int(0) : (offset == 0 ? int(1000 + i * 700) : int(1000 + i * 700 + options.defaultTickScale)),
        "wrong ask price"
      );
      // bids are rounded up when misaligned
      assertEq(
        kdl.getOffer(Bid, i).logPrice(), i >= pricePoints - STEP ? int(0) : -int(1000 + i * 700), "wrong bid price"
      );
    }
  }

  function test_extremes_max_log_price_bid() public {
    test_extremes_min_max_log_price(Bid, false);
  }

  function test_extremes_max_log_price_ask() public {
    test_extremes_min_max_log_price(Ask, false);
  }

  function test_extremes_min_log_price_bid() public {
    test_extremes_min_max_log_price(Bid, true);
  }

  function test_extremes_min_log_price_ask() public {
    test_extremes_min_max_log_price(Ask, true);
  }

  function test_extremes_min_max_log_price(OfferType ba, bool min) internal {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params;

    // With price at MAX_LOG_PRICE dual appears at MIN_LOG_PRICE, so there can only be two offers, and no offset
    int baseQuoteLogPriceIndex0 = min ? MIN_LOG_PRICE : MAX_LOG_PRICE;
    params.pricePoints = 2;
    params.stepSize = 1;
    logPriceOffset = 0;

    (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
      .createDistribution({
      from: 0,
      to: 2,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: ba == Bid ? params.stepSize + 1 : 0,
      bidGives: 2 ** 96 - 1,
      askGives: 2 ** 96 - 1,
      pricePoints: params.pricePoints,
      stepSize: params.stepSize
    });
    vm.prank(maker);
    kdl.populate(bidDistribution, askDistribution, params, 0, 0);

    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    if (ba == Bid) {
      assertEq(bestBid.logPrice(), min ? MAX_LOG_PRICE : MIN_LOG_PRICE, "wrong bid price");
      assertEq(bestBid.gives(), 2 ** 96 - 1, "wrong bid gives");
      assertEq(bestAsk.isLive(), false, "ask should not be live");
    } else {
      assertEq(bestAsk.logPrice(), min ? MIN_LOG_PRICE : MAX_LOG_PRICE, "wrong ask price");
      assertEq(bestAsk.gives(), 2 ** 96 - 1, "wrong ask gives");
      assertEq(bestBid.isLive(), false, "bid should not be live");
    }
  }

  function test_extremes_max_offset_bid() public {
    test_extremes_max_offset(Bid);
  }

  function test_extremes_max_offset_ask() public {
    test_extremes_max_offset(Ask);
  }

  function test_extremes_max_offset(OfferType ba) internal {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params;

    int baseQuoteLogPriceIndex0 = 0;
    params.pricePoints = 2;
    params.stepSize = 1;
    logPriceOffset = uint(MAX_LOG_PRICE);

    (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
      .createDistribution({
      from: 0,
      to: 2,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: ba == Bid ? params.stepSize + 1 : 0,
      bidGives: 2 ** 96 - 1,
      askGives: 2 ** 96 - 1,
      pricePoints: params.pricePoints,
      stepSize: params.stepSize
    });
    vm.prank(maker);
    kdl.populate(bidDistribution, askDistribution, params, 0, 0);

    if (ba == Bid) {
      deal($(base), address(taker), type(uint).max);
      deal($(quote), address(kdl), 2 ** 96);
    } else {
      deal($(base), address(kdl), 2 ** 96);
      deal($(quote), address(taker), type(uint).max);
    }
    // Take order
    vm.prank(taker);
    (uint takerGot, uint takerGave,,) =
      mgv.marketOrderByLogPrice(ba == Bid ? lo : olKey, MAX_LOG_PRICE, MAX_SAFE_VOLUME, false);
    assertGt(takerGot + takerGave, 0, "offer should succeed");

    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    if (ba == Bid) {
      assertEq(bestBid.logPrice(), 0, "wrong bid price");
      assertEq(bestAsk.logPrice(), MAX_LOG_PRICE, "wrong ask price");
    } else {
      assertEq(bestBid.logPrice(), 0, "wrong bid price");
      assertEq(bestAsk.logPrice(), MAX_LOG_PRICE, "wrong ask price");
    }
  }

  function test_extremes_outside_range_bid() public {
    test_extremes_outside_range(Bid);
  }

  function test_extremes_outside_range_ask() public {
    test_extremes_outside_range(Ask);
  }

  function test_extremes_outside_range(OfferType ba) internal {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params;

    int baseQuoteLogPriceIndex0 = MAX_LOG_PRICE;
    params.pricePoints = 2;
    params.stepSize = 1;
    logPriceOffset = 1;

    vm.expectRevert("mgv/writeOffer/logPrice/outOfRange");
    vm.prank(maker);
    kdl.populateFromOffset({
      from: 0,
      to: 2,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: ba == Bid ? params.stepSize + 1 : 0,
      bidGives: 2 ** 96 - 1,
      askGives: 2 ** 96 - 1,
      parameters: params,
      baseAmount: 0,
      quoteAmount: 0
    });
  }

  function test_extremes_min_log_price_max_offset_bid() public {
    test_extremes_min_log_price_max_offset(Bid);
  }

  function test_extremes_min_log_price_max_offset_ask() public {
    test_extremes_min_log_price_max_offset(Ask);
  }

  function test_extremes_min_log_price_max_offset(OfferType ba) internal {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params;

    // With price at MAX_LOG_PRICE dual appears at MIN_LOG_PRICE, so there can only be two offers, and no offset
    int baseQuoteLogPriceIndex0 = MIN_LOG_PRICE;
    params.pricePoints = 2;
    params.stepSize = 1;
    logPriceOffset = uint(MAX_LOG_PRICE - MIN_LOG_PRICE);

    (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
      .createDistribution({
      from: 0,
      to: 2,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: ba == Bid ? params.stepSize + 1 : 0,
      bidGives: 2 ** 96 - 1,
      askGives: 2 ** 96 - 1,
      pricePoints: params.pricePoints,
      stepSize: params.stepSize
    });
    vm.prank(maker);
    kdl.populate(bidDistribution, askDistribution, params, 0, 0);

    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    if (ba == Bid) {
      assertEq(bestBid.logPrice(), MAX_LOG_PRICE, "wrong bid price");
      assertEq(bestBid.gives(), 2 ** 96 - 1, "wrong bid gives");
      assertEq(bestAsk.isLive(), false, "ask should not be live");
    } else {
      assertEq(bestAsk.logPrice(), MAX_LOG_PRICE, "wrong ask price");
      assertEq(bestAsk.gives(), 2 ** 96 - 1, "wrong ask gives");
      assertEq(bestBid.isLive(), false, "bid should not be live");
    }
  }

  function test_extremes_many_price_points() public {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    uint provAsk = reader.getProvision(olKey, kdl.offerGasreq(), bufferedGasprice);
    uint provBid = reader.getProvision(lo, kdl.offerGasreq(), bufferedGasprice);

    GeometricKandel.Params memory params;

    int baseQuoteLogPriceIndex0 = 2;
    params.pricePoints = 1000;
    params.stepSize = 11;
    logPriceOffset = 77;

    (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
      .createDistribution({
      from: 0,
      to: 1000,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: params.pricePoints / 2,
      bidGives: 2 ** 96 - 1,
      askGives: 2 ** 96 - 1,
      pricePoints: params.pricePoints,
      stepSize: params.stepSize
    });
    vm.prank(maker);
    kdl.populate{value: (provAsk + provBid) * params.pricePoints}(bidDistribution, askDistribution, params, 0, 0);
  }

  function test_allExternalFunctions_differentCallers_correctAuth() public virtual {
    // Arrange
    bytes[] memory selectors = AllMethodIdentifiersTest.getAllMethodIdentifiers(vm, getAbiPath());

    assertGt(selectors.length, 0, "Some functions should be loaded");

    for (uint i = 0; i < selectors.length; i++) {
      // Assert that all are called - to decode the selector search in the abi file
      vm.expectCall(address(kdl), selectors[i]);
    }

    // Act/assert - invoke all functions - if any are missing, add them.

    // No auth
    kdl.BASE();
    kdl.MGV();
    kdl.NO_ROUTER();
    kdl.OFFER_GASREQ();
    kdl.QUOTE();
    kdl.RESERVE_ID();
    kdl.TICK_SCALE();
    kdl.admin();
    kdl.checkList(new IERC20[](0));
    kdl.depositFunds(0, 0);
    kdl.getOffer(Ask, 0);
    kdl.indexOfOfferId(Ask, 42);
    kdl.offerIdOfIndex(Ask, 0);
    kdl.offerGasreq();
    kdl.offeredVolume(Ask);
    kdl.params();
    kdl.pending(Ask);
    kdl.reserveBalance(Ask);
    kdl.provisionOf(olKey, 0);
    kdl.router();
    kdl.baseQuoteLogPriceOffset();
    kdl.createDistribution(0, 0, 0, 0, 0, 0, 0, 0, 0);
    kdl.createDistribution(0, 0, 0, 0, 0, 0);

    CoreKandel.Distribution memory dist;
    GeometricKandel.Params memory params = getParams(kdl);
    params.pricePoints = 2;
    CheckAuthArgs memory args;
    args.callee = $(kdl);
    args.callers = dynamic([address($(mgv)), maker, $(this), $(kdl)]);
    args.revertMessage = "AccessControlled/Invalid";

    // Only admin
    args.allowed = dynamic([address(maker)]);
    checkAuth(args, abi.encodeCall(kdl.activate, dynamic([IERC20(base)])));
    checkAuth(args, abi.encodeCall(kdl.approve, (base, taker, 42)));
    checkAuth(args, abi.encodeCall(kdl.setAdmin, (maker)));
    checkAuth(args, abi.encodeCall(kdl.retractAndWithdraw, (0, 0, 0, 0, 0, maker)));
    checkAuth(args, abi.encodeCall(kdl.setGasprice, (42)));
    checkAuth(args, abi.encodeCall(kdl.setStepSize, (2)));
    checkAuth(args, abi.encodeCall(kdl.setGasreq, (42)));
    checkAuth(args, abi.encodeCall(kdl.setRouter, (kdl.router())));
    checkAuth(args, abi.encodeCall(kdl.setBaseQuoteLogPriceOffset, (1)));

    checkAuth(args, abi.encodeCall(kdl.populate, (dist, dist, params, 0, 0)));
    checkAuth(args, abi.encodeCall(kdl.populateFromOffset, (0, 0, 0, 0, 0, 0, 0, params, 0, 0)));
    checkAuth(args, abi.encodeCall(kdl.populateChunkFromOffset, (0, 0, 0, 0, 0, 0)));

    checkAuth(args, abi.encodeCall(kdl.populateChunk, (dist, dist)));
    checkAuth(args, abi.encodeCall(kdl.retractOffers, (0, 0)));
    checkAuth(args, abi.encodeCall(kdl.withdrawFromMangrove, (0, maker)));
    checkAuth(args, abi.encodeCall(kdl.withdrawFunds, (0, 0, maker)));

    // Only Mgv
    MgvLib.OrderResult memory oResult = MgvLib.OrderResult({makerData: bytes32(0), mgvData: ""});
    args.allowed = dynamic([address($(mgv))]);
    checkAuth(args, abi.encodeCall(kdl.makerExecute, mockCompleteFillBuyOrder(1, 1)));
    checkAuth(args, abi.encodeCall(kdl.makerPosthook, (mockCompleteFillBuyOrder(1, 1), oResult)));
  }
}
