// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  MangroveAmplifier,
  SmartRouter,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";

import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK, MIN_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

contract MgvAmplifierTest is StratTest {
  RouterProxyFactory internal routerFactory; // deployed routerFactory
  SimpleAaveLogic internal aaveLogic; // deployed simple aave router implementation
  MangroveAmplifier internal mgvAmplifier; // MangroveAmplifier contract

  uint defaultLogicGasreq = 250_000;
  uint aaveLogicGasreq = 475_000;

  IERC20 weth;
  IERC20 wbtc;
  IERC20 dai;
  OLKey dai_weth;
  OLKey dai_wbtc;

  // roles
  address deployer = freshAddress("deployer"); // deploys contracts
  address owner = freshAddress("owner"); // owns an amplified offer
  address taker = freshAddress("taker"); // takes offers

  function setUp() public virtual override {
    // forking polygon in order to use AAVE
    PinnedPolygonFork fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    weth = IERC20(fork.get("WETH.e"));
    dai = IERC20(fork.get("DAI.e"));
    wbtc = IERC20(fork.get("WBTC.e"));

    // default test market
    base = TestToken($(weth));
    quote = TestToken($(dai));

    mgv = setupMangrove();

    vm.startPrank(deployer);
    routerFactory = new RouterProxyFactory();
    aaveLogic = new SimpleAaveLogic(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    mgvAmplifier = new MangroveAmplifier(mgv, routerFactory, deployer);
    mgvAmplifier.activate(weth);
    mgvAmplifier.activate(dai);
    mgvAmplifier.activate(wbtc);
    vm.stopPrank();

    reader = new MgvReader($(mgv));

    dai_weth = OLKey(address(dai), address(weth), options.defaultTickSpacing);
    dai_wbtc = OLKey(address(dai), address(wbtc), options.defaultTickSpacing);

    olKey = dai_weth; // test defaults
    lo = dai_weth.flipped();

    mgv.activate(dai_weth, options.defaultFee, options.density96X32, options.gasbase);
    mgv.activate(dai_wbtc, options.defaultFee, options.density96X32, options.gasbase);

    // preparing owner account (either using SimpleRouter or SimpleAaveRouter)
    deal($(dai), owner, 10_000 * 10 ** 18);
    vm.deal(owner, 10 ether);
    AbstractRouter ownerRouter = activateOwnerRouter(dai, MangroveOffer(mgvAmplifier), owner, type(uint).max);
    vm.startPrank(owner);
    // approves router to pull aDai from owner's account
    aaveLogic.overlying(dai).approve(address(ownerRouter), type(uint).max);
    // approves POOL to pull DAI in order to obtain aDai
    dai.approve(address(aaveLogic.POOL()), type(uint).max);
    // supplies 5000 DAI to aave
    aaveLogic.POOL().supply($(dai), 5000 * 10 ** 18, owner, 0);
    assertEq(aaveLogic.overlying(dai).balanceOf(owner), 5000 * 10 ** 18);
    vm.stopPrank();

    deal($(weth), taker, 1 ether);
    deal($(wbtc), taker, 10 ** 8);
    vm.deal(taker, 1 ether);
    vm.prank(taker);
    weth.approve($(mgv), type(uint).max);
    vm.prank(taker);
    wbtc.approve($(mgv), type(uint).max);
  }

  function test_deployment() public {
    assertEq(mgvAmplifier.admin(), deployer, "Inccorect admin");
    assertTrue(address(mgvAmplifier.ROUTER_IMPLEMENTATION()) != address(0), "No router");
    assertEq(address(mgvAmplifier.ROUTER_FACTORY()), address(routerFactory), "No factory");
  }

  bool use_aave_logic;

  function build_amplified_offer_args()
    internal
    view
    returns (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr)
  {
    vr = new MangroveAmplifier.VariableBundleParams[](2);
    fx.outbound_tkn = dai;
    fx.outVolume = 1000 * 10 ** 18;
    if (use_aave_logic) {
      fx.outboundLogic = aaveLogic;
    }

    vr[0].inbound_tkn = weth;
    vr[0].tick = TickLib.tickFromVolumes({inboundAmt: 1 ether, outboundAmt: 2000 * 10 ** 18});
    vr[0].gasreq = use_aave_logic ? aaveLogicGasreq : defaultLogicGasreq;
    vr[0].provision = 0.02 ether;
    vr[0].tickSpacing = options.defaultTickSpacing;

    vr[1].inbound_tkn = wbtc;
    vr[1].tick = TickLib.tickFromVolumes({inboundAmt: 10 ** 8, outboundAmt: 27_000 * 10 ** 18});
    vr[1].gasreq = use_aave_logic ? aaveLogicGasreq : defaultLogicGasreq;
    vr[1].provision = 0.02 ether;
    vr[1].tickSpacing = options.defaultTickSpacing;
  }

  event InitBundle(uint indexed bundleId);
  event EndBundle();
  event NewOwnedOffer(bytes32 indexed olKeyHash, uint indexed offerId, address indexed owner);

  function test_newBundle_logs() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    expectFrom(address(mgvAmplifier));
    emit InitBundle(0);
    expectFrom(address(mgvAmplifier));
    emit NewOwnedOffer(dai_weth.hash(), 1, owner);
    expectFrom(address(mgvAmplifier));
    emit NewOwnedOffer(dai_wbtc.hash(), 1, owner);
    expectFrom(address(mgvAmplifier));
    emit EndBundle();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    assertEq(bundleId, 0, "Incorrect bundle Id");
    assertEq(mgvAmplifier.ownerOf(bundleId, dai), owner, "Incorrect bundle owner");
  }

  function run_partial_fill_scenario() internal {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    // we check OfferSuccess is emitted, this will not be emitted if trade fails or posthook reverts
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferSuccess({olKeyHash: dai_wbtc.hash(), taker: taker, id: 1, takerWants: 0, takerGives: 0});

    // taker sells  0.004 btc to get 100 dai
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_wbtc, TickLib.tickFromVolumes(0.004 * 10 ** 8, 100 * 10 ** 18), 0.004 * 10 ** 8, false);
    vm.stopPrank();

    assertTrue(takerGot + fee >= 100 * 10 ** 18, "unexpected takerGot");
    assertEq(takerGave, 0.004 * 10 ** 8, "unexpected takerGave");
    assertEq(bounty, 0, "trade failed");

    // checking that offers were correctly updated
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);

    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 1000 * 10 ** 18 - takerGot - fee);
    }
  }

  function test_partial_fill_of_one_offer_updates_bundle_simple_logic() public {
    use_aave_logic = false;
    run_partial_fill_scenario();
  }

  function test_partial_fill_of_one_offer_updates_bundle_aave_logic() public {
    use_aave_logic = true;
    run_partial_fill_scenario();
  }

  function test_complete_fill_of_one_offer_retracts_bundle() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    // we check OfferSuccess is emitted, this will not be emitted if trade fails or posthook reverts
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferSuccess({olKeyHash: dai_wbtc.hash(), taker: taker, id: 1, takerWants: 0, takerGives: 0});

    // taker "buys" all DAI
    vm.startPrank(taker);
    (uint takerGot,,, uint fee) = mgv.marketOrderByTick(dai_wbtc, Tick.wrap(MAX_TICK), 1000 * 10 ** 18, true);
    vm.stopPrank();
    assertEq(takerGot + fee, 1000 * 10 ** 18, "Failed trade");
    // checking that offers were correctly updated
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);

    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 0);
    }
  }

  bool partialFill;

  function makerExecute(MgvLib.SingleOrder calldata) external returns (bytes32) {
    vm.startPrank(taker);
    (uint takerGot,, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_wbtc, Tick.wrap(MAX_TICK), (partialFill ? 10 ** 4 : 10 ** 8), false);
    vm.stopPrank();
    // checking step 3.1
    if (!partialFill) {
      assertEq(takerGot + fee, 1000 * 10 ** 18, "step 3.1"); // the dai from amplifier
    } else {
      assertTrue(takerGot > 0, "step 3.1");
    }
    assertEq(bounty, 0); // no failure
    return "";
  }

  event GotPaid();

  receive() external payable {
    emit GotPaid();
  }

  /// 1.  owner posts a bundle of offers [`ofr_dai_weth`,`ofr_dai_btc`] : [dai, (weth, wbtc)]
  /// 2. `this` posts an offer `ofr` on Mangrove dai_weth offer list which runs a market order on the dai_wbtc one when executed
  /// 3. `this` executes a market order on dai_weth that consumes first `ofr`
  ////// 3.1 when mangrove executes `ofr` a market order on dai_btc is triggered and consumes entirely (if `partialFill=false`) or partially (if `partialFill=true`) `ofr_dai_btc`
  ////// 3.2 `ofr_dai_btc`'s execution attempts at updating `ofr_dai_weth` on an offer list that is now locked. So it sets it to renege mode
  ////// 3.3  market order launched at step 3. continues and consumes `ofr_dai_weth` which now reneges and sends bounty to `ofr` owner aka `this`
  function run_scenario() internal {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    // step 1.
    vm.prank(owner);
    mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    deal($(weth), address(this), 1 ether);
    deal($(dai), address(this), 100 * 10 ** 18);

    weth.approve($(mgv), type(uint).max);
    dai.approve($(mgv), type(uint).max);

    // step 2.
    mgv.newOfferByTick{value: 0.1 ether}(dai_weth, Tick.wrap(MIN_TICK), 1 * 10 ** 18, 1_000_000, 0);

    // checks 3.2
    // ofr_dai_weth sets expiry date of ofr_dai_wbtc to now
    vm.expectEmit(true, true, true, false, address(mgvAmplifier));
    emit SetExpiry({olKeyHash: dai_weth.hash(), offerId: 1, date: block.timestamp});
    // market order proceeds and ofr_dai_weth indeed fails
    vm.expectEmit(true, true, true, false, address(mgvAmplifier));
    emit LogIncident({
      olKeyHash: dai_weth.hash(),
      offerId: 1,
      makerData: "ExpirableForwarder/expired",
      mgvData: bytes32(0)
    });

    // checks 3.3
    expectFrom(address(this));
    emit GotPaid();

    // step 3.
    mgv.marketOrderByTick(dai_weth, Tick.wrap(MAX_TICK), 1000 ether, false);
  }

  function test_retracting_an_offer_in_a_locked_offer_list_makes_it_expire() public {
    partialFill = false;
    run_scenario();
  }

  function test_updating_an_offer_in_a_locked_offer_list_makes_it_expire() public {
    partialFill = true;
    run_scenario();
  }

  function test_external_bundle_update_volume() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    mgvAmplifier.updateBundle(bundleId, dai, 50 * 10 ** 18, false, 0);
    vm.stopPrank();

    // checking offers of the bundle have been updated to the new outbound volume
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 50 * 10 ** 18);
    }
  }

  function test_external_bundle_update_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    mgvAmplifier.updateBundle(bundleId, dai, 0, true, block.timestamp + 1000);
    vm.stopPrank();

    // checking bundle expiry date
    assertEq(mgvAmplifier.expiring(bytes32(0), bundleId), block.timestamp + 1000, "Incorrect expiry");
  }

  function test_external_bundle_update_volume_and_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    mgvAmplifier.updateBundle(bundleId, dai, 50 * 10 ** 18, true, block.timestamp + 1000);
    vm.stopPrank();

    assertEq(mgvAmplifier.expiring(bytes32(0), bundleId), block.timestamp + 1000, "Incorrect expiry");

    // checking offers of the bundle have been updated to the new outbound volume
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 50 * 10 ** 18);
    }
  }

  function test_external_bundle_update_volume_and_expiry_noop() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    mgvAmplifier.updateBundle(bundleId, dai, 0, false, block.timestamp + 1000);
    vm.stopPrank();

    assertEq(mgvAmplifier.expiring(bytes32(0), bundleId), 0, "Incorrect expiry");
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 1000 * 10 ** 18);
    }
  }

  function test_external_bundle_retract() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    uint balWeiBefore = owner.balance;
    uint freeWei = mgvAmplifier.retractBundle(bundleId, dai);
    vm.stopPrank();
    assertEq(owner.balance - balWeiBefore, freeWei, "Incorrect freeWei");

    // checking offers of the bundle have been retracted
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 0);
    }
  }
}
