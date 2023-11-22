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
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

contract MgvAmplifierTest is StratTest {
  RouterProxyFactory internal routerFactory; // deployed routerFactory
  SimpleAaveLogic internal aaveLogic; // deployed simple aave router implementation
  MangroveAmplifier internal mgvAmplifier; // MangroveAmplifier contract

  uint defaultLogicGasreq = 250_000;

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

    deal($(dai), owner, 10_000 * 10 ** 18);
    vm.deal(owner, 10 ether);
    activateOwnerRouter(dai, MangroveOffer(mgvAmplifier), owner, type(uint).max);

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

  function simpleAmplifiedOffer()
    internal
    view
    returns (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr)
  {
    vr = new MangroveAmplifier.VariableBundleParams[](2);
    fx.outbound_tkn = dai;
    fx.outVolume = 1000 * 10 ** 18;

    vr[0].inbound_tkn = weth;
    vr[0].inVolume = 0.5 ether;
    vr[0].gasreq = defaultLogicGasreq;
    vr[0].provision = 0.02 ether;
    vr[0].tick = options.defaultTickSpacing;

    vr[1].inbound_tkn = wbtc;
    vr[1].inVolume = 0.04 * 10 ** 8;
    vr[1].gasreq = defaultLogicGasreq;
    vr[1].provision = 0.02 ether;
    vr[1].tick = options.defaultTickSpacing;
  }

  event InitBundle(uint indexed bundleId);
  event EndBundle();
  event NewOwnedOffer(bytes32 indexed olKeyHash, uint indexed offerId, address indexed owner);

  function test_newBundle_logs() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      simpleAmplifiedOffer();

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

  function test_partial_fill_of_one_offer_updates_bundle() public {
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      simpleAmplifiedOffer();
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
  //TODO
  // * test complete fill
  // * test locked offer list puts offer in reneging mode both for partial fill (update failed) and complete fill (retract failed)
  // * test aave logic is correctly called
}
