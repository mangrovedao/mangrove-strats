// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  MangroveAmplifier,
  SmartRouter,
  RouterProxyFactory,
  RouterProxy,
  AbstractRoutingLogic
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {SimpleAbracadabraLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAbracadabraLogic.sol";
import {IPoolAddressesProvider} from
  "@mgv-strats/src/strategies/vendor/aave/v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {ICauldronV4} from "@mgv-strats/src/strategies/vendor/abracadabra/interfaces/ICauldronV4.sol";

import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail, Local} from "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK, MIN_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {RenegingForwarder} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {VmSafe} from "@mgv/lib/forge-std/src/Vm.sol";

contract MgvAmplifierTest is StratTest {
  RouterProxyFactory internal routerFactory; // deployed routerFactory
  SimpleAaveLogic internal aaveLogic; // deployed simple aave router implementation
  SimpleAbracadabraLogic internal abracadabraLogic; // deployed simple abracadabra router implementation
  MangroveAmplifier internal mgvAmplifier; // MangroveAmplifier contract

  // uint defaultLogicGasreq = 250_000;
  // uint aaveLogicGasreq = 475_000;

  uint defaultLogicGasreq = 275_000;
  uint aaveLogicGasreq = 500_000;
  uint abracadabraLogicGasreq = 500_000;

  IERC20 weth;
  IERC20 wbtc;
  IERC20 dai;
  IERC20 mim;

  OLKey dai_weth;
  OLKey dai_wbtc;

  // roles
  address deployer = freshAddress("deployer"); // deploys contracts
  address owner = freshAddress("owner"); // owns an amplified offer
  address taker = freshAddress("taker"); // takes offers

  function setUp() public virtual override {
    // forking polygon in order to use AAVE to test some logic
    PinnedPolygonFork fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    weth = IERC20(fork.get("WETH.e"));
    dai = IERC20(fork.get("DAI.e"));
    wbtc = IERC20(fork.get("WBTC.e"));
    mim = IERC20(fork.get("MIM.e"));

    // default test market
    base = TestToken($(weth));
    quote = TestToken($(dai));

    mgv = setupMangrove();

    vm.startPrank(deployer);
    routerFactory = new RouterProxyFactory();
    aaveLogic = new SimpleAaveLogic(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    abracadabraLogic = new SimpleAbracadabraLogic(mim, ICauldronV4(fork.get("AbracadabraCauldron")));
    mgvAmplifier = new MangroveAmplifier(mgv, routerFactory, new SmartRouter(address(0)));
    mgvAmplifier.activate(weth);
    mgvAmplifier.activate(dai);
    mgvAmplifier.activate(wbtc);
    vm.stopPrank();

    reader = new MgvReader($(mgv));

    dai_weth = OLKey(address(dai), address(weth), options.defaultTickSpacing);
    dai_wbtc = OLKey(address(dai), address(wbtc), options.defaultTickSpacing);

    olKey = dai_weth; // test defaults
    lo = dai_weth.flipped();

    mgv.activate(dai_weth, options.defaultFee, options.density96X32 * 10 ** 7, options.gasbase);
    mgv.activate(dai_weth.flipped(), options.defaultFee, options.density96X32 * 10 ** 7, options.gasbase);

    // making density of dai_wbtc higher in order to test partial fill scenario
    mgv.activate(dai_wbtc, options.defaultFee, options.density96X32 * 2 * 10 ** 9, options.gasbase);
    mgv.activate(dai_wbtc.flipped(), options.defaultFee, options.density96X32 * 10 ** 4, options.gasbase);

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

  function build_amplified_offer_args()
    internal
    view
    returns (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr)
  {
    return (build_amplified_offer_args(AbstractRoutingLogic(address(0)), AbstractRoutingLogic(address(0))));
  }

  function build_amplified_offer_args(AbstractRoutingLogic inboundLogic, AbstractRoutingLogic outboundLogic)
    internal
    view
    returns (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr)
  {
    vr = new MangroveAmplifier.VariableBundleParams[](2);
    fx.outbound_tkn = dai;
    fx.outVolume = 1000 * 10 ** 18;
    if (address(outboundLogic) != address(0)) {
      fx.outboundLogic = outboundLogic;
    }

    vr[0].inbound_tkn = weth;
    vr[0].tick = TickLib.tickFromVolumes({inboundAmt: 1 ether, outboundAmt: 2000 * 10 ** 18});
    vr[0].gasreq = address(outboundLogic) != address(0) ? aaveLogicGasreq : defaultLogicGasreq;
    vr[0].provision = 0.02 ether;
    vr[0].tickSpacing = options.defaultTickSpacing;
    if (address(inboundLogic) != address(0)) {
      vr[0].inboundLogic = inboundLogic;
    }

    vr[1].inbound_tkn = wbtc;
    vr[1].tick = TickLib.tickFromVolumes({inboundAmt: 10 ** 8, outboundAmt: 27_000 * 10 ** 18});
    vr[1].gasreq = address(outboundLogic) != address(0) ? aaveLogicGasreq : defaultLogicGasreq;
    vr[1].provision = 0.02 ether;
    vr[1].tickSpacing = options.defaultTickSpacing;
    if (address(inboundLogic) != address(0)) {
      vr[1].inboundLogic = inboundLogic;
    }
  }

  event InitBundle(uint indexed bundleId, IERC20 indexed outbound_tkn);
  event EndBundle();
  event NewOwnedOffer(bytes32 indexed olKeyHash, uint indexed offerId, address indexed owner);
  // SmartRouter
  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRoutingLogic logic);

  function test_newBundle_no_logic_logs() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    expectFrom(address(mgvAmplifier));
    emit InitBundle(0, fx.outbound_tkn);
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

  function test_bundle_owner() public {
    MangroveAmplifier.FixedBundleParams memory fx1;
    MangroveAmplifier.VariableBundleParams[] memory vr1 = new MangroveAmplifier.VariableBundleParams[](1);

    fx1.outbound_tkn = weth;
    fx1.outVolume = 1000 * 10 ** 18;

    vr1[0].inbound_tkn = dai;
    vr1[0].tick = TickLib.tickFromVolumes({inboundAmt: 10_000 * 10 ** 18, outboundAmt: 1 ether});
    vr1[0].gasreq = defaultLogicGasreq;
    vr1[0].provision = 0.02 ether;
    vr1[0].tickSpacing = options.defaultTickSpacing;

    MangroveAmplifier.FixedBundleParams memory fx2;
    MangroveAmplifier.VariableBundleParams[] memory vr2 = new MangroveAmplifier.VariableBundleParams[](1);

    fx2.outbound_tkn = wbtc;
    fx2.outVolume = 1000 * 10 ** 8;

    vr2[0].inbound_tkn = dai;
    vr2[0].tick = TickLib.tickFromVolumes({inboundAmt: 10_000 * 10 ** 18, outboundAmt: 1 ether});
    vr2[0].gasreq = defaultLogicGasreq;
    vr2[0].provision = 0.02 ether;
    vr2[0].tickSpacing = options.defaultTickSpacing;

    vm.prank(owner);
    uint bundleId1 = mgvAmplifier.newBundle{value: 0.04 ether}(fx1, vr1);

    vm.prank(taker);
    uint bundleId2 = mgvAmplifier.newBundle{value: 0.04 ether}(fx2, vr2);

    assertEq(mgvAmplifier.ownerOf(bundleId1, weth), owner, "Incorrect bundle owner");
    assertEq(mgvAmplifier.ownerOf(bundleId2, wbtc), taker, "Incorrect bundle owner");

    assertEq(mgvAmplifier.ownerOf(bundleId1, wbtc), address(0), "Incorrect bundle owner");
    assertEq(mgvAmplifier.ownerOf(bundleId2, weth), address(0), "Incorrect bundle owner");
  }

  function test_newBundle_with_insufficient_provision_reverts_with_expected_message() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.expectRevert("MgvAmplifier/NotEnoughProvisions");
    mgvAmplifier.newBundle{value: 0.02 ether}(fx, vr);
  }

  function test_newBundle_with_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    fx.expiryDate = block.timestamp + 1000;
    expectFrom(address(mgvAmplifier));
    emit SetReneging({olKeyHash: bytes32(0), offerId: 0, date: block.timestamp + 1000, volume: 0});
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    assertEq(bundleId, 0, "Incorrect bundle Id");
  }

  function test_newBundle_outbound_logic_logs() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args(AbstractRoutingLogic(address(0)), aaveLogic);

    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(dai, dai_weth.hash(), 1, aaveLogic);

    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(dai, dai_wbtc.hash(), 1, aaveLogic);

    vm.prank(owner);
    mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
  }

  function test_newBundle_inbound_logic_logs() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args(AbstractRoutingLogic(aaveLogic), AbstractRoutingLogic(address(0)));

    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(weth, dai_weth.hash(), 1, aaveLogic);
    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(wbtc, dai_wbtc.hash(), 1, aaveLogic);

    vm.prank(owner);
    mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
  }

  function test_newBundle_inbound_outbound_logic_logs() public {
    address someLogic = freshAddress("logic");
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args({inboundLogic: aaveLogic, outboundLogic: AbstractRoutingLogic(someLogic)});

    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(weth, dai_weth.hash(), 1, aaveLogic);
    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(dai, dai_weth.hash(), 1, AbstractRoutingLogic(someLogic));

    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(wbtc, dai_wbtc.hash(), 1, aaveLogic);
    expectFrom(address(mgvAmplifier.router(owner)));
    emit SetRouteLogic(dai, dai_wbtc.hash(), 1, AbstractRoutingLogic(someLogic));

    vm.prank(owner);
    mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
  }

  // event OfferSuccess(
  //   bytes32 indexed olKeyHash, address indexed taker, uint indexed id, uint takerWants, uint takerGives
  // );

  function fromAddressToBytes32(address x) internal pure returns (bytes32 res) {
    assembly {
      res := x
    }
  }

  function run_partial_fill_scenario(bool withAaveOutbound) internal {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
    build_amplified_offer_args(
      AbstractRoutingLogic(address(0)), withAaveOutbound ? aaveLogic : AbstractRoutingLogic(address(0))
    );
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    // taker sells  0.004 btc to get 100 dai
    vm.startPrank(taker);
    vm.recordLogs();
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_wbtc, TickLib.tickFromVolumes(0.004 * 10 ** 8, 100 * 10 ** 18), 0.004 * 10 ** 8, false);
    VmSafe.Log[] memory entries = vm.getRecordedLogs();
    vm.stopPrank();

    // we check OfferSuccess is emitted, this will not be emitted if trade fails or posthook reverts
    // we cannot use vm.expectEmit because multiple events are emitted in the same transaction
    bytes32 topic0 = keccak256("OfferSuccess(bytes32,address,uint256,uint256,uint256)");

    bool found = false;
    for (uint i; i < entries.length; i++) {
      if (entries[i].topics[0] == topic0) {
        found = true;
        assertEq(entries[i].topics[1], dai_wbtc.hash(), "unexpected olKeyHash");
        assertEq(entries[i].topics[2], fromAddressToBytes32(taker), "unexpected taker");
        assertEq(entries[i].topics[3], bytes32(uint(1)), "unexpected id");
        // assertEq(entries[i].data, abi.encode(uint(0),uint(0)), "unexpected takerWants");
        break;
      }
    }
    assertTrue(found, "OfferSuccess not emitted");

    assertTrue(takerGot + fee >= 100 * 10 ** 18, "unexpected takerGot");
    assertEq(takerGave, 0.004 * 10 ** 8, "unexpected takerGave");
    assertEq(bounty, 0, "trade failed");

    // checking that offers were correctly updated
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);

    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 1000 * 10 ** 18 - takerGot - fee);
    }
  }

  function test_partial_fill_of_one_offer_updates_bundle_simple_logic() public {
    run_partial_fill_scenario(false);
  }

  function test_partial_fill_of_one_offer_updates_bundle_aave_logic() public {
    run_partial_fill_scenario(true);
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
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);

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
    // selling btc for dai with fillWants = true to control whether the offer is fully filled or not
    uint takerWants = partialFill ? 500 * 10 ** 18 : 1000 * 10 ** 18;
    (uint takerGot,, uint bounty, uint fee) = mgv.marketOrderByTick(dai_wbtc, Tick.wrap(MAX_TICK), takerWants, true);
    vm.stopPrank();
    // checking step 3.1
    assertEq(takerGot + fee, takerWants, "step 3.1"); // the dai from amplifier
    assertEq(bounty, 0); // no failure
    return bytes32(0);
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
    // ofr_dai_weth sets volume to now
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    if (partialFill) {
      // if partial fill reneging on volume
      emit SetReneging({olKeyHash: dai_weth.hash(), offerId: 1, date: 0, volume: 500 * 10 ** 18});
    } else {
      // if complete fill reneging on date
      emit SetReneging({olKeyHash: dai_weth.hash(), offerId: 1, date: block.timestamp, volume: 0});
    }
    // market order proceeds and ofr_dai_weth indeed fails
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    if (partialFill) {
      emit LogIncident({
        olKeyHash: dai_weth.hash(),
        offerId: 1,
        makerData: "RenegingForwarder/overSized",
        mgvData: "mgv/makerRevert"
      });
    } else {
      emit LogIncident({
        olKeyHash: dai_weth.hash(),
        offerId: 1,
        makerData: "RenegingForwarder/expired",
        mgvData: "mgv/makerRevert"
      });
    }

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

  function test_partial_fill_with_residual_below_density_retracts_offer() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    // min amount of dai to be able to post of the dai_wbtc offer list.
    uint dai_wbtc_min_volume = reader.minVolume(dai_wbtc, defaultLogicGasreq);
    uint dai_weth_min_volume = reader.minVolume(dai_weth, defaultLogicGasreq);
    // computing how much btc to sell in order to get (1000 - dai_wbtc_min_volume) dai
    uint target = 1000 * 10 ** 18 - dai_wbtc_min_volume;
    // 1 wbtc is 27000 dai so 1/27000 wbtc is 1 dai and 1/27000 * target is the amount of wbtc to sell
    uint amount = target / (27_000 * 10 ** 10);

    // taking just enough so that offer fails to repost on wbtc but not on weth
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_wbtc, TickLib.tickFromVolumes(0.004 * 10 ** 8, 100 * 10 ** 18), amount - 352, false);
    vm.stopPrank();
    assertEq(bounty, 0, "trade failed");
    assertTrue(1000 * 10 ** 18 - takerGot - fee < dai_wbtc_min_volume, "partial fill will repost");
    assertTrue(1000 * 10 ** 18 - takerGot - fee >= dai_weth_min_volume, "partial fill will not repost");

    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      if (address(bundle[i].inbound_tkn) == address(wbtc)) {
        assertEq(offer.gives(), 0, "Offer should be retracted");
      } else {
        assertEq(offer.gives(), 1000 * 10 ** 18 - takerGot - fee, "Offer should be updated");
      }
    }
  }

  function test_fail_to_deliver_retracts_bundle() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    // removing liquidity from the owner's account so that offer fails to deliver
    deal($(dai), owner, 0);

    expectFrom(address(mgvAmplifier));
    emit LogIncident({
      olKeyHash: dai_weth.hash(),
      offerId: 1,
      makerData: "mgvOffer/abort/getFailed",
      mgvData: "mgv/makerRevert"
    });

    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_weth, Tick.wrap(MAX_TICK), 1 ether, true);
    vm.stopPrank();
    assertEq(takerGot + fee, 0, "Offer did not fail");
    assertTrue(bounty > 0, "Offer did not fail");
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 0, "Offer should be retracted");
    }
  }

  function test_external_bundle_update_volume() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    vm.expectRevert("MgvAmplifier/unauthorized");
    mgvAmplifier.updateBundle(bundleId, dai, 50 * 10 ** 18, false, 0);

    vm.prank(owner);
    mgvAmplifier.updateBundle(bundleId, dai, 50 * 10 ** 18, false, 0);

    // checking offers of the bundle have been updated to the new outbound volume
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
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

    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(bytes32(0), bundleId);
    // checking bundle expiry date
    assertEq(cond.date, block.timestamp + 1000, "Incorrect expiry");
  }

  function test_external_bundle_update_volume_and_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    mgvAmplifier.updateBundle(bundleId, dai, 50 * 10 ** 18, true, block.timestamp + 1000);
    vm.stopPrank();

    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(bytes32(0), bundleId);
    assertEq(cond.date, block.timestamp + 1000, "Incorrect expiry");

    // checking offers of the bundle have been updated to the new outbound volume
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
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

    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(bytes32(0), bundleId);
    assertEq(cond.date, 0, "Incorrect expiry");
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
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

    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    uint balWeiBefore = owner.balance;

    vm.expectRevert("MgvAmplifier/unauthorized");
    mgvAmplifier.retractBundle(bundleId, dai);

    vm.prank(owner);
    uint freeWei = mgvAmplifier.retractBundle(bundleId, dai);
    assertEq(owner.balance - balWeiBefore, freeWei, "Incorrect freeWei");

    // checking offers of the bundle have been retracted
    MangroveAmplifier.BundledOffer[] memory bundle = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    for (uint i; i < bundle.length; i++) {
      Offer offer = mgv.offers(
        OLKey({inbound_tkn: $(bundle[i].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing}),
        bundle[i].offerId
      );
      assertEq(offer.gives(), 0);
    }
  }

  function test_offer_expiry_before_bundle_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    fx.expiryDate = block.timestamp + 1000;
    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    vm.stopPrank();

    // checking bundle expiry date
    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(bytes32(0), bundleId);
    assertEq(cond.date, block.timestamp + 1000, "Incorrect expiry");

    // setting expiry date of the first offer to now
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    emit SetReneging({olKeyHash: dai_weth.hash(), offerId: 1, date: block.timestamp, volume: 0});
    vm.prank(owner);
    mgvAmplifier.setReneging(dai_weth.hash(), 1, block.timestamp, 0);

    // market order proceeds and ofr_dai_weth indeed fails
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    emit LogIncident({
      olKeyHash: dai_weth.hash(),
      offerId: 1,
      makerData: "RenegingForwarder/expired",
      mgvData: "mgv/makerRevert"
    });

    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_weth, Tick.wrap(MAX_TICK), 1 ether, true);
    vm.stopPrank();
    assertTrue(takerGot == 0 && takerGave == 0 && bounty > 0 && fee == 0, "unexpected trade");
  }

  function test_bundle_expiry_before_offer_expiry() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();

    fx.expiryDate = block.timestamp;
    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    vm.stopPrank();

    // checking bundle expiry date
    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(bytes32(0), bundleId);
    assertEq(cond.date, block.timestamp, "Incorrect expiry");

    // setting expiry date of the first offer to now
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    emit SetReneging({olKeyHash: dai_weth.hash(), offerId: 1, date: block.timestamp + 1000, volume: 0});
    vm.prank(owner);
    mgvAmplifier.setReneging(dai_weth.hash(), 1, block.timestamp + 1000, 0);

    // market order proceeds and ofr_dai_weth indeed fails
    vm.expectEmit(true, true, true, true, address(mgvAmplifier));
    emit LogIncident({
      olKeyHash: dai_weth.hash(),
      offerId: 1,
      makerData: "MgvAmplifier/expiredBundle",
      mgvData: "mgv/makerRevert"
    });
    // taker sells  0.004 btc to get 100 dai
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_weth, Tick.wrap(MAX_TICK), 1 ether, true);
    vm.stopPrank();
    assertTrue(takerGot == 0 && takerGave == 0 && bounty > 0 && fee == 0, "unexpected trade");
  }

  //////////////////////////
  /// test on max volume ///
  //////////////////////////

  function test_offer_cannot_take_more_than_max_volume() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    uint offerId = offers[0].offerId;
    OLKey memory olKey =
      OLKey({inbound_tkn: $(offers[0].inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing});

    // get the outbound_tkn volume
    uint outboundVolume = mgv.offers(dai_weth, offerId).gives();

    mgvAmplifier.setReneging(olKey.hash(), offerId, 0, outboundVolume / 2);

    vm.stopPrank();
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), outboundVolume / 2 + 1, true);
    vm.stopPrank();
    assertTrue(takerGot == 0 && takerGave == 0 && bounty > 0 && fee == 0, "unexpected trade");
    bool isLive = mgv.offers(olKey, offerId).isLive();
    assertTrue(!isLive, "offer should be dead");
  }

  function test_lock_market() public {
    OLKey memory olKey = dai_weth;
    forceLockMarket(mgv, olKey);
    assertTrue(mgv.locked(olKey), "market should be locked");
    forceUnlockMarket(mgv, olKey);
    assertTrue(!mgv.locked(olKey), "market should not be locked");
  }

  function test_max_volume_triggered_and_untriggered() public {
    // init bundle
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    MangroveAmplifier.BundledOffer memory offerTaken = offers[0];
    MangroveAmplifier.BundledOffer memory offerNotTaken = offers[1];
    OLKey memory notTakenOLKey =
      OLKey({inbound_tkn: $(offerNotTaken.inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing});
    OLKey memory takenOLKey =
      OLKey({inbound_tkn: $(offerTaken.inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing});
    uint outboundVolume = mgv.offers(takenOLKey, offerTaken.offerId).gives();
    uint outboundVolumeNotTaken = mgv.offers(notTakenOLKey, offerNotTaken.offerId).gives();

    // simulate locked market
    // This will happen if this market order is triggered within an offer execution logic on the market
    forceLockMarket(mgv, notTakenOLKey);
    vm.prank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(takenOLKey, Tick.wrap(MAX_TICK), outboundVolume / 2, true);
    forceUnlockMarket(mgv, notTakenOLKey);

    // check that the offer worked
    assertTrue(takerGot + fee == outboundVolume / 2 && takerGave > 0 && bounty == 0 && fee > 0, "unexpected trade");

    // check that the max volume was set to half of the outbound volume
    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(notTakenOLKey.hash(), offerNotTaken.offerId);
    assertEq(cond.volume, outboundVolume / 2, "Incorrect max volume");
    uint giveOfferNotTaken = mgv.offers(notTakenOLKey, offerNotTaken.offerId).gives();
    assertEq(giveOfferNotTaken, outboundVolumeNotTaken, "Volume should not have been updated");

    // calling on unlocked market shoudl set back max volume to 0 and update all offers
    vm.prank(taker);
    (takerGot, takerGave, bounty, fee) =
      mgv.marketOrderByTick(takenOLKey, Tick.wrap(MAX_TICK), outboundVolume / 4, true);

    // check that the offer worked
    // and that the max volume was set back to 0 as offer was updated
    assertTrue(takerGot + fee == outboundVolume / 4 && takerGave > 0 && bounty == 0 && fee > 0, "unexpected trade");
    RenegingForwarder.Condition memory cond2 = mgvAmplifier.reneging(notTakenOLKey.hash(), offerNotTaken.offerId);
    assertEq(cond2.volume, 0, "Incorrect max volume");

    // check volume has been updated to the correct new volume (i.e. maxVolume - (takerGot + fee))
    giveOfferNotTaken = mgv.offers(notTakenOLKey, offerNotTaken.offerId).gives();
    assertEq(giveOfferNotTaken, outboundVolumeNotTaken / 4, "Volume should have been updated");
    assertEq(giveOfferNotTaken, cond.volume - (takerGot + fee), "Volume should have been updated");
  }

  function test_griefing_attack_poc() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.prank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    MangroveAmplifier.BundledOffer memory offerTaken = offers[0];
    MangroveAmplifier.BundledOffer memory offerNotTaken = offers[1];
    OLKey memory notTakenOLKey =
      OLKey({inbound_tkn: $(offerNotTaken.inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing});
    OLKey memory takenOLKey =
      OLKey({inbound_tkn: $(offerTaken.inbound_tkn), outbound_tkn: $(dai), tickSpacing: options.defaultTickSpacing});
    uint outboundVolume = mgv.offers(takenOLKey, offerTaken.offerId).gives();
    uint outboundVolumeNotTaken = mgv.offers(notTakenOLKey, offerNotTaken.offerId).gives();

    // simulate locked market
    // This will happen if this market order is triggered within an offer execution logic on the market
    forceLockMarket(mgv, notTakenOLKey);
    vm.prank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) =
      mgv.marketOrderByTick(takenOLKey, Tick.wrap(MAX_TICK), outboundVolume / 2, true);
    forceUnlockMarket(mgv, notTakenOLKey);

    // check that the offer worked
    assertTrue(takerGot + fee == outboundVolume / 2 && takerGave > 0 && bounty == 0 && fee > 0, "unexpected trade");

    // check that the max volume was set to half of the outbound volume
    RenegingForwarder.Condition memory cond = mgvAmplifier.reneging(notTakenOLKey.hash(), offerNotTaken.offerId);
    assertEq(cond.volume, outboundVolume / 2, "Incorrect max volume");
    uint giveOfferNotTaken = mgv.offers(notTakenOLKey, offerNotTaken.offerId).gives();
    assertEq(giveOfferNotTaken, outboundVolumeNotTaken, "Volume should not have been updated");

    // take the max volume + 1 on the not taken offer (the one with a set max volume)
    // this should renege the offer
    vm.prank(taker);
    (takerGot, takerGave, bounty, fee) =
      mgv.marketOrderByTick(notTakenOLKey, Tick.wrap(MAX_TICK), cond.volume + 1, true);

    // check that the offer did not work
    // and that the max volume was set back to 0 as offer was updated
    assertTrue(takerGot == 0 && takerGave == 0 && bounty > 0 && fee == 0, "unexpected trade");
  }

  function test_volume_limit_is_reset_after_partial_fill() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args();
    vm.startPrank(owner);
    uint bundleId = mgvAmplifier.newBundle{value: 0.04 ether}(fx, vr);

    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId, fx.outbound_tkn);
    uint offerId = offers[0].offerId;

    // get the outbound_tkn volume
    uint outboundVolume = mgv.offers(dai_weth, offerId).gives();

    mgvAmplifier.setReneging(dai_weth.hash(), offerId, block.timestamp + 1000, outboundVolume / 2);
    vm.stopPrank();
    assertEq(mgvAmplifier.reneging(dai_weth.hash(), offerId).volume, outboundVolume / 2, "Incorrect max volume");
    assertEq(mgvAmplifier.reneging(dai_weth.hash(), offerId).date, block.timestamp + 1000, "Incorrect date");

    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferSuccess({olKeyHash: dai_weth.hash(), taker: taker, id: offerId, takerWants: 0, takerGives: 0});
    vm.prank(taker);
    (uint takerGot,, uint bounty, uint fee) =
      mgv.marketOrderByTick(dai_weth, Tick.wrap(MAX_TICK), outboundVolume / 3, true);
    assertEq(takerGot + fee, outboundVolume / 3, "Incorrect takerGot");
    assertEq(bounty, 0, "Incorrect bounty");
    assertEq(mgvAmplifier.reneging(dai_weth.hash(), offerId).volume, 0, "volume was not reset");
    assertEq(mgvAmplifier.reneging(dai_weth.hash(), offerId).date, block.timestamp + 1000, "date should not change");

    // checking offer is still live
    assertEq(mgv.offers(dai_weth, offerId).gives(), outboundVolume / 2 - takerGot - fee, "Incorrect outbound volume");
  }
}
