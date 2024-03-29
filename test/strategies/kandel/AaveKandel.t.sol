// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {
  AaveKandel, AavePooledRouter
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {PoolAddressProviderMock} from "@mgv-strats/script/toy/AaveMock.sol";
import {AaveCaller, IPoolAddressesProvider} from "@mgv-strats/test/lib/agents/AaveCaller.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

contract AaveKandelTest is CoreKandelTest {
  PinnedPolygonFork fork;
  AavePooledRouter router;
  AaveKandel aaveKandel;
  bool useForkAave = true;
  IPoolAddressesProvider aave;

  receive() external payable {}

  function __setForkEnvironment__() internal override {
    if (useForkAave) {
      fork = new PinnedPolygonFork(39880000);
      fork.setUp();
      options.gasprice = 90;
      options.gasbase = 68_000;
      options.defaultFee = 30;
      mgv = setupMangrove();
      reader = new MgvReader($(mgv));
      base = TestToken(fork.get("WETH.e"));
      quote = TestToken(fork.get("USDC.e"));
      olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
      lo = olKey.flipped();
      setupMarket(olKey);
      aave = IPoolAddressesProvider(fork.get("AaveAddressProvider"));
    } else {
      super.__setForkEnvironment__();
      aave = IPoolAddressesProvider(address(new PoolAddressProviderMock(dynamic([address(base), address(quote)]))));

      // Assume tokens behave weirdly here
      base.transferResponse(TestToken.MethodResponse.MissingReturn);
      quote.approveResponse(TestToken.MethodResponse.MissingReturn);
    }
  }

  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    uint kandel_gasreq = 800_000;
    router = address(router) == address(0) ? new AavePooledRouter(aave) : router;
    AaveKandel aaveKandel_ = new AaveKandel({
      mgv: IMangrove($(mgv)),
      olKeyBaseQuote: olKey,
      gasreq: kandel_gasreq,
      routerParams: Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: strict})
    });

    router.bind(address(aaveKandel_));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKandel_.setAdmin(deployer);
    return aaveKandel_;
  }

  function precisionForAssert() internal pure override returns (uint) {
    return 1;
  }

  function getAbiPath() internal pure override returns (string memory) {
    return "/out/AaveKandel.sol/AaveKandel.json";
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), maker, "Incorrect owner");
    assertEq(base.balanceOf(address(router)), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(Ask) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(Bid) > 0, "Incorrect initial reserve balance of quote");
    assertEq(
      router.overlying(base).balanceOf(address(router)),
      kdl.reserveBalance(Ask),
      "Router should have all its base on AAVE"
    );
    assertEq(
      router.overlying(quote).balanceOf(address(router)),
      kdl.reserveBalance(Bid),
      "Router should have all its quote on AAVE"
    );
  }

  function test_first_offer_sends_first_puller_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }

  function test_not_first_offer_sends_proceed_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    // faking buffer on the router
    deal($(base), $(router), 1 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "", "Unexpected returned data");
  }

  function test_not_first_offer_sends_first_puller_to_posthook_when_buffer_is_small() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    // faking small buffer on the router
    deal($(base), $(router), 0.09 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }

  function test_first_puller_posthook_calls_pushAndSupply() public {
    MgvLib.SingleOrder memory order =
      mockCompleteFillBuyOrder({takerWants: 0.1 ether, tick: TickLib.tickFromVolumes(120 * 10 ** 6, 0.1 ether)});
    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: "IS_FIRST_PULLER", mgvData: "mgv/tradeSuccess"});

    //1. faking accumulated outbound on the router
    deal($(base), $(router), 1 ether);
    //2. faking accumulated inbound on kandel
    deal($(quote), $(kdl), 1000 * 10 ** 6);

    uint makerBalance = kdl.reserveBalance(Bid);
    uint baseAave = router.overlying(base).balanceOf(address(router));
    uint quoteAave = router.overlying(quote).balanceOf(address(router));
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    assertApproxEqAbs(kdl.reserveBalance(Bid), makerBalance, 1, "Maker balance should be invariant");
    assertEq(base.balanceOf(address(router)), 0, "Router did not flush base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router did not flush quote buffer");
    assertEq(
      router.overlying(base).balanceOf(address(router)),
      baseAave + 1 ether,
      "Router should have supplied its base buffer on AAVE"
    );
    assertApproxEqAbs(
      router.overlying(quote).balanceOf(address(router)),
      quoteAave + 1000 * 10 ** 6,
      1,
      "Router should have supplied maker's quote on AAVE"
    );
  }

  function test_sharing_liquidity_between_strats(uint16 baseAmount, uint16 quoteAmount) public {
    deal($(base), maker, baseAmount);
    deal($(quote), maker, quoteAmount);
    GeometricKandel kdl_ = __deployKandel__(maker, maker, false);
    assertEq(kdl_.FUND_OWNER(), kdl.FUND_OWNER(), "Strats should have the same reserveId");

    uint baseBalance = kdl.reserveBalance(Ask);
    uint quoteBalance = kdl.reserveBalance(Bid);

    vm.prank(maker);
    kdl.depositFunds(baseAmount, quoteAmount);

    assertEq(kdl.reserveBalance(Ask), kdl_.reserveBalance(Ask), "funds are not shared");
    assertEq(kdl.reserveBalance(Bid), kdl_.reserveBalance(Bid), "funds are not shared");
    assertApproxEqAbs(kdl.reserveBalance(Bid), quoteBalance + quoteAmount, 1, "Incorrect quote amount");
    assertApproxEqAbs(kdl.reserveBalance(Ask), baseBalance + baseAmount, 1, "Incorrect base amount");
  }

  function test_offerLogic_sharingLiquidityBetweenStratsNoDonation_offersSucceedAndFundsPushedToAave() public {
    offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 0,
      allBaseOnAave: true,
      allQuoteOnAave: true
    });
  }

  function test_offerLogic_sharingLiquidityBetweenStratsFirstOfferDonated_offersSucceedAndPushesBaseToAave() public {
    offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 1,
      allBaseOnAave: true,
      allQuoteOnAave: false
    });
  }

  function test_offerLogic_sharingLiquidityBetweenStratsBothOffersDonated_offersSucceedAndNoFundsPushedToAave() public {
    offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 3,
      allBaseOnAave: false,
      allQuoteOnAave: false
    });
  }

  function offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave(
    uint donationMultiplier,
    bool allBaseOnAave,
    bool allQuoteOnAave
  ) internal {
    GeometricKandel kdl_ = __deployKandel__(maker, maker, false);
    assertEq(kdl_.FUND_OWNER(), kdl.FUND_OWNER(), "Strats should have the same reserveId");

    (, Offer bestAsk) = getBestOffers();
    populateSingle({
      kandel: kdl_,
      index: 4,
      base: bestAsk.gives(),
      quote: bestAsk.wants(),
      firstAskIndex: 0,
      expectRevert: ""
    });

    deal($(base), $(router), donationMultiplier * bestAsk.gives());

    vm.prank(taker);
    (uint takerGot,,, uint fee) = mgv.marketOrderByTick(olKey, bestAsk.tick(), bestAsk.gives() * 2, true);

    assertEq(takerGot + fee, bestAsk.gives() * 2, "both asks should be taken");

    if (allBaseOnAave) {
      assertEq(
        router.overlying(base).balanceOf(address(router)),
        kdl.reserveBalance(Ask),
        "Router should have all its base on AAVE unless donation made it unnecessary to pull from AAVE"
      );
    }
    if (allQuoteOnAave) {
      assertEq(
        router.overlying(quote).balanceOf(address(router)),
        kdl.reserveBalance(Bid),
        "Router should have all its quote on AAVE unless donation made it unnecessary to pull from AAVE for first offer"
      );
    }
  }

  function test_strats_wih_same_admin_but_different_id_do_not_share_liquidity(uint16 baseAmount, uint16 quoteAmount)
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

  function executeAttack() public {
    // context base should not be available to redeem for the router, for this attack to succeed
    (, uint takerGave, uint bounty,) = mgv.marketOrderByVolume(olKey, 0.1 ether, type(uint96).max, true);

    require(takerGave == 0 && bounty > 0, "attack failed");
  }

  function test_liquidity_flashloan_attack() public {
    AaveCaller attacker = new AaveCaller(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    deal($(quote), address(this), 1 ether);
    quote.approve({spender: address(mgv), amount: type(uint).max});
    attacker.setCallbackAddress(address(this));
    uint gas = gasleft();
    uint bestAsk = mgv.best(olKey);
    bytes memory cd = abi.encodeWithSelector(this.executeAttack.selector, bestAsk);
    uint assetSupply = attacker.get_supply(base);
    uint nativeBalance = address(this).balance;
    try attacker.flashloan(base, assetSupply - 1, cd) {
      gas = gas - gasleft();
      assertTrue(true, "Flashloan attack succeeded!");
      console.log("Total profit of the attack:", toFixed(address(this).balance - nativeBalance, 18));
      console.log("Gas cost:", gas);
    } catch {
      assertTrue(false, "Flashloan attack failed");
    }
  }

  function test_liquidity_borrow_clean_attack() public {
    // base is weth and has a borrow cap, so trying the attack on quote
    address dai = fork.get("DAI.e");
    AaveCaller attacker = new AaveCaller(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    deal($(base), address(this), 1 ether);
    base.approve({spender: address(mgv), amount: type(uint).max});
    uint quoteSupply = attacker.get_supply(quote); // quote in 6 decimals
    // mocking up a big flashloan of usdc
    deal(dai, address(attacker), quoteSupply * 2 * 10 ** 12); // dai has 18 decimals
    attacker.approveLender(IERC20(dai));
    attacker.supply(IERC20(dai), quoteSupply * 2 * 10 ** 12);
    uint nativeBal = address(this).balance;
    uint gas = gasleft(); // adding flash loan overhead
    try attacker.borrow(quote, quoteSupply - 1) {
      (, uint takerGave, uint bounty,) = sellToBestAs(address(this), 0.1 ether);
      require(takerGave == 0 && bounty > 0, "Attack failed");
      gas = gas - gasleft() + 300_000; // adding flashloan cost
      console.log(
        "Attack successful, %s collected for an overhead of %s gas units",
        toFixed(address(this).balance - nativeBal, 18),
        gas
      );
      (Global global,) = mgv.config(OLKey(address(0), address(0), 0));
      uint attacker_cost = gas * global.gasprice() * 1e6;
      console.log("Gas cost of the attack: %s native tokens", toFixed(attacker_cost, 18));
    } catch Error(string memory reason) {
      console.log(reason);
    }
  }

  function test_liquidity_borrow_marketOrder_attack() public {
    GeometricKandel.Params memory otherParams;
    otherParams.pricePoints = 137;
    otherParams.stepSize = 1;
    /// adding as many offers as possible (adding more will stack overflow when failing offer will cascade)
    deployOtherKandel(0.1 ether, 100 * 10 ** 6, 100, otherParams);
    //printOrderBook($(quote), $(base));
    // base is weth and has a borrow cap, so trying the attack on quote
    address dai = fork.get("DAI.e");
    AaveCaller attacker = new AaveCaller(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    deal($(base), address(this), 1 ether);
    base.approve({spender: address(mgv), amount: type(uint).max});
    uint quoteSupply = attacker.get_supply(quote); // quote in 6 decimals
    // mocking up a big flashloan of usdc
    deal(dai, address(attacker), quoteSupply * 140 * 10 ** 10); // dai has 18 decimals
    attacker.approveLender(IERC20(dai));
    attacker.supply(IERC20(dai), quoteSupply * 140 * 10 ** 10);
    uint gas = gasleft(); // adding flash loan overhead
    try attacker.borrow(quote, quoteSupply - 1) {
      // borrow is ~180K
      (, uint takerGave, uint bounty,) =
        mgv.marketOrderByVolume({olKey: lo, takerWants: 10, takerGives: 1 ether, fillWants: false});

      require(takerGave == 0 && bounty > 0, "Attack failed");
      gas = gas - gasleft() + 400_000; // adding flashloan cost + repay of borrow
      console.log("Attack successful, %s collected for an overhead of %s gas units", toFixed(bounty, 18), gas);
      (Global global, Local local) = mgv.config(olKey);
      console.log("Gasbase is ", local.offer_gasbase());
      uint attacker_cost = gas * global.gasprice() * 1e6;
      console.log(
        "Gas cost of the attack (gasprice %s gwei): %s native tokens", global.gasprice(), toFixed(attacker_cost, 18)
      );
    } catch Error(string memory reason) {
      console.log(reason);
    }
    printOfferList(lo);
  }

  function test_cannot_create_aaveKandel_with_aToken_for_base() public {
    AaveCaller attacker = new AaveCaller(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    IERC20 aToken = attacker.overlying(base);
    vm.expectRevert("AaveKandel/cannotTradeAToken");
    new AaveKandel({
      mgv: IMangrove($(mgv)),
      gasreq: 700_000,
      olKeyBaseQuote: OLKey(address(aToken), address(quote), 1),
      routerParams: Direct.RouterParams({routerImplementation: router, fundOwner: address(0), strict: false})
    });
  }

  function test_cannot_create_aaveKandel_with_aToken_for_quote() public {
    AaveCaller attacker = new AaveCaller(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    IERC20 aToken = attacker.overlying(quote);
    vm.expectRevert("AaveKandel/cannotTradeAToken");
    new AaveKandel({
      mgv: IMangrove($(mgv)),
      gasreq: 700_000,
      olKeyBaseQuote: OLKey(address(base), address(aToken), 1),
      routerParams: Direct.RouterParams({routerImplementation: router, fundOwner: address(0), strict: false})
    });
  }
}
