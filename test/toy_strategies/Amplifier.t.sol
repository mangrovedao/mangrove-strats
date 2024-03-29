// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import "@mgv/test/lib/forks/Polygon.sol";
import "@mgv-strats/src/toy_strategies/offer_maker/Amplifier.sol";
import {Local} from "@mgv/src/core/MgvLib.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";

contract AmplifierTest is StratTest {
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  PolygonFork fork;

  address payable taker;
  Amplifier strat;
  OLKey olKeyWethDai;
  uint constant GASREQ = 250_000;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(39880000); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    // setup tokens, markets and approve them
    dai = IERC20(fork.get("DAI.e"));
    weth = IERC20(fork.get("WETH.e"));
    usdc = IERC20(fork.get("USDC.e"));
    olKeyWethDai = OLKey($(weth), $(dai), options.defaultTickSpacing);
    olKey = OLKey($(usdc), $(weth), options.defaultTickSpacing);
    lo = olKey.flipped();

    setupMarket(olKeyWethDai);
    setupMarket(olKey);

    // setup separate taker and give some native token (for gas) + USDC and DAI
    taker = freshAddress("taker");
    deal(taker, 10_000_000);

    deal($(usdc), taker, cash(usdc, 10_000));
    deal($(dai), taker, cash(dai, 10_000));

    // approve DAI and USDC on Mangrove for taker
    vm.startPrank(taker);
    dai.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();
  }

  function test_success_fill() public {
    deployStrat();

    execTraderStratWithFillSuccess();
  }

  function test_deprovisionDeadOffers() public {
    deployStrat();

    execTraderStratDeprovisionDeadOffers();
  }

  function test_success_partialFill() public {
    deployStrat();

    execTraderStratWithPartialFillSuccess();
  }

  function test_fallback() public {
    deployStrat();

    execTraderStratWithFallback();
  }

  function test_offerAlreadyLive() public {
    deployStrat();

    execTraderStratWithOfferAlreadyLive();
  }

  function deployStrat() public {
    strat = new Amplifier({
      mgv: IMangrove($(mgv)),
      base: weth,
      stable1: usdc,
      stable2: dai,
      tickSpacing1: olKey.tickSpacing,
      tickSpacing2: olKeyWethDai.tickSpacing,
      admin: $(this) // for ease, set this contract (will be Test runner) as admin for the strat
    });
  }

  function postAndFundOffers(uint makerGivesAmount, uint makerWantsAmountDAI, uint makerWantsAmountUSDC, uint gasreq)
    public
    returns (uint offerId1, uint offerId2)
  {
    (offerId1, offerId2) = strat.newAmplifiedOffers{value: 2 ether}({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmountUSDC, // USDC
      wants2: makerWantsAmountDAI, // DAI
      gasreq: gasreq
    });
  }

  function takeOffer(uint makerWantsAmount, IERC20 makerWantsToken, uint offerId)
    public
    returns (uint takerGot, uint takerGave, uint bounty)
  {
    OLKey memory _olKey = OLKey($(weth), $(makerWantsToken), olKey.tickSpacing);
    Tick tick = mgv.offers(_olKey, offerId).tick();
    // try to take one of the offers (using the separate taker account)
    vm.prank(taker);
    (takerGot, takerGave, bounty,) =
      mgv.marketOrderByTick({olKey: _olKey, maxTick: tick, fillVolume: makerWantsAmount, fillWants: false});
  }

  function execTraderStratWithPartialFillSuccess() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    weth.approve($(strat.router()), type(uint).max);

    deal($(weth), $(this), cash(weth, 5));

    // post offers with Amplifier liquidity
    (uint offerId1, uint offerId2) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    //only take half of the offer
    (uint takerGot, uint takerGave,) = takeOffer(makerWantsAmountDAI / 2, dai, offerId1);

    // assert that
    uint offerGaveMinusFee = reader.minusFee(olKeyWethDai.flipped(), makerGivesAmount / 2);
    assertTrue(((takerGot - offerGaveMinusFee) * 10_000) / (makerGivesAmount / 2) < 10, "taker got wrong amount");
    assertEq(takerGave, makerWantsAmountDAI / 2, "taker gave wrong amount");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    Offer offer_on_dai = mgv.offers(olKeyWethDai, offerId1);
    Offer offer_on_usdc = mgv.offers(lo, offerId2);
    assertTrue(offer_on_dai.isLive(), "weth->dai offer should not have been retracted");
    assertTrue(offer_on_usdc.isLive(), "weth->usdc offer should not have been retracted");
  }

  function execTraderStratWithFillSuccess() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    weth.approve($(strat.router()), type(uint).max);

    deal($(weth), $(this), cash(weth, 10));

    (uint offerId1, uint offerId2) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    (uint takerGot, uint takerGave,) = takeOffer(makerWantsAmountDAI, dai, offerId1);

    // assert that
    assertEq(takerGot, reader.minusFee(olKeyWethDai.flipped(), makerGivesAmount), "taker got wrong amount");
    assertTrue((makerWantsAmountDAI - takerGave) * 100000 / makerWantsAmountDAI < 10, "taker gave wrong amount");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    Offer offer_on_dai = mgv.offers(olKeyWethDai, offerId1);
    Offer offer_on_usdc = mgv.offers(olKey, offerId2);
    assertTrue(!offer_on_dai.isLive(), "weth->dai offer should have been retracted");
    assertTrue(!offer_on_usdc.isLive(), "weth->usdc offer should have been retracted");
  }

  function execTraderStratDeprovisionDeadOffers() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    weth.approve($(strat.router()), type(uint).max);

    deal($(weth), $(this), cash(weth, 10));

    (uint offerId1,) = postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    takeOffer(makerWantsAmountDAI, dai, offerId1);

    // check native balance before deprovision
    uint nativeBalanceBeforeRetract = $(this).balance;
    strat.retractOffers(true);

    // assert that
    assertTrue(nativeBalanceBeforeRetract < $(this).balance, "offers was not deprovisioned");
  }

  function execTraderStratWithOfferAlreadyLive() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    weth.approve($(strat.router()), type(uint).max);

    deal($(weth), $(this), cash(weth, 10));

    (uint offerId1, uint offerId2) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    vm.expectRevert("Amplifier/offer1AlreadyActive");
    postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    strat.retractOffer(lo, offerId1, false);

    vm.expectRevert("Amplifier/offer2AlreadyActive");
    postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    Offer offer_on_dai = mgv.offers(olKeyWethDai, offerId1);
    Offer offer_on_usdc = mgv.offers(lo, offerId2);
    assertTrue(offer_on_dai.isLive(), "weth->dai offer should not have been retracted");
    assertTrue(!offer_on_usdc.isLive(), "weth->usdc offer should have been retracted");
  }

  function execTraderStratWithFallback() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    // not giving the start any WETH, the offer will therefor fail when taken
    (uint offerId1, uint offerId2) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC, GASREQ);

    (uint takerGot, uint takerGave, uint bounty) = takeOffer(makerWantsAmountUSDC, usdc, offerId2);

    // assert that
    assertEq(takerGot, 0, "taker got wrong amount");
    assertEq(takerGave, 0, "taker gave wrong amount");
    assertTrue(bounty > 0, "taker did not get any bounty");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    Offer offer_on_dai = mgv.offers(olKeyWethDai, offerId1);
    Offer offer_on_usdc = mgv.offers(olKey, offerId2);
    assertTrue(!offer_on_dai.isLive(), "weth->dai offer should have been retracted");
    assertTrue(!offer_on_usdc.isLive(), "weth->usdc offer should have been retracted");
  }
}
