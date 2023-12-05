// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import {StratTest, MangroveOffer} from "@mgv-strats/test/lib/StratTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IOrderLogic} from "@mgv-strats/src/strategies/interfaces/IOrderLogic.sol";
import {IERC20, OLKey, Offer} from "@mgv/src/core/MgvLib.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {OfferGasReqBaseTest} from "@mgv/test/lib/gas/OfferGasReqBase.t.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";

import {
  MangroveAmplifier,
  SmartRouter,
  RouterProxyFactory,
  RouterProxy,
  AbstractRoutingLogic
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

import {MgvLib} from "@mgv/src/core/MgvLib.sol";
import "@mgv/src/preprocessed/Structs.post.sol";

import {console} from "@mgv/lib/Test2.sol";

contract MangroveAmplifierGasreqBaseTest is StratTest, OfferGasReqBaseTest {
  IERC20[] internal testTokens;

  TestToken internal outbound;

  RouterProxyFactory internal routerFactory;
  SimpleAaveLogic internal aaveLogic;
  MangroveAmplifier internal mgvAmplifier;

  AbstractRoutingLogic internal inb_logic;
  AbstractRoutingLogic internal outb_logic;

  uint internal amplifiedOffer3;
  uint internal amplifiedOffer5;
  uint internal amplifiedOffer8;
  uint internal amplifiedOffer10;
  uint internal amplifiedOffer30;
  uint internal amplifiedOffer50;

  function setUp() public virtual override {
    super.setUp();
    setUpAmplifier(AbstractRoutingLogic(address(0)), AbstractRoutingLogic(address(0)), 50);
    setUpAllAmplifiedOffers();
  }

  function setUpAllAmplifiedOffers() public virtual {
    amplifiedOffer3 = setUpAmplifiedOffer(3);
    amplifiedOffer5 = setUpAmplifiedOffer(5);
    amplifiedOffer8 = setUpAmplifiedOffer(8);
    amplifiedOffer10 = setUpAmplifiedOffer(10);
    amplifiedOffer30 = setUpAmplifiedOffer(30);
    amplifiedOffer50 = setUpAmplifiedOffer(50);
  }

  function tostr(uint _i) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
      return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len;
    while (_i != 0) {
      k = k - 1;
      uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
      bytes1 b1 = bytes1(temp);
      bstr[k] = b1;
      _i /= 10;
    }
    return string(bstr);
  }

  function setUpAmplifier(AbstractRoutingLogic _inb_logic, AbstractRoutingLogic _outb_logic, uint _maxToken) internal {
    OLKey memory olKey;
    olKey.tickSpacing = 1;

    routerFactory = new RouterProxyFactory();
    mgvAmplifier = new MangroveAmplifier(mgv, routerFactory);
    inb_logic = _inb_logic;
    outb_logic = _outb_logic;

    outbound = new TestToken(address(this), "amplified", "AMPL", 18);
    olKey.outbound_tkn = address(outbound);
    // 3000 ether to pull 3 times
    deal($(outbound), address(this), 100000 ether);
    mgvAmplifier.activate(outbound);
    activateOwnerRouter(outbound, MangroveOffer(mgvAmplifier), address(this), type(uint).max);

    IERC20[] memory _testTokens = new IERC20[](_maxToken);

    for (uint i = 0; i < _maxToken; i++) {
      TestToken token = new TestToken(
        address(this),
        string.concat("ampl", tostr(i)),
        string.concat("TEST", tostr(i)),
        18
      );
      olKey.inbound_tkn = address(token);
      setupMarket(olKey);

      mgvAmplifier.activate(token);
      activateOwnerRouter(token, MangroveOffer($(mgvAmplifier)), address(this));
      _testTokens[i] = token;
    }
    testTokens = _testTokens;
  }

  /// @param nToken The number of tokens to be used in the test.
  function setUpAmplifiedOffer(uint nToken) public virtual returns (uint bundleId) {
    IERC20[] memory toUse = new IERC20[](nToken);
    for (uint i = 0; i < nToken; i++) {
      toUse[i] = testTokens[i];
    }
    (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr) =
      build_amplified_offer_args(outbound, toUse, inb_logic, outb_logic);
    bundleId = mgvAmplifier.newBundle{value: 0.5 ether * nToken}(fx, vr);
  }

  function mock_partial_fill_order(OLKey memory _olKey, uint _offerId)
    internal
    returns (uint makerExecutGas, uint makerPostHookGas)
  {
    // ptentially warming storage up
    Offer offer = mgv.offers(_olKey, _offerId);

    MgvLib.SingleOrder memory sor;
    MgvLib.OrderResult memory result;

    MangroveAmplifier m = mgvAmplifier;

    sor.olKey = _olKey;
    sor.offer = offer;
    sor.offerId = _offerId;
    sor.takerWants = offer.gives() / 2;
    sor.takerGives = offer.wants() / 2;

    // TODO: success instead
    result.makerData = bytes32(0);
    result.mgvData = "mgv/tradeSuccess";

    deal(_olKey.inbound_tkn, $(mgvAmplifier), sor.takerGives);

    vm.startPrank($(mgv));

    makerExecutGas = gasleft();
    m.makerExecute(sor);
    makerExecutGas = makerExecutGas - gasleft();

    makerPostHookGas = gasleft();
    m.makerPosthook(sor, result);
    makerPostHookGas = makerPostHookGas - gasleft();

    vm.stopPrank();
  }

  function mock_complete_fill_order(OLKey memory _olKey, uint _offerId)
    internal
    returns (uint makerExecutGas, uint makerPostHookGas)
  {
    // ptentially warming storage up
    Offer offer = mgv.offers(_olKey, _offerId);

    MgvLib.SingleOrder memory sor;
    MgvLib.OrderResult memory result;

    MangroveAmplifier m = mgvAmplifier;

    sor.olKey = _olKey;
    sor.offer = offer;
    sor.offerId = _offerId;
    sor.takerWants = offer.gives();
    sor.takerGives = offer.wants();

    result.makerData = bytes32(0);
    result.mgvData = "mgv/tradeSuccess";

    deal(_olKey.inbound_tkn, $(mgvAmplifier), sor.takerGives);

    vm.startPrank($(mgv));

    makerExecutGas = gasleft();
    m.makerExecute(sor);
    makerExecutGas = makerExecutGas - gasleft();

    makerPostHookGas = gasleft();
    m.makerPosthook(sor, result);
    makerPostHookGas = makerPostHookGas - gasleft();

    vm.stopPrank();
  }

  function build_amplified_offer_args(
    IERC20 _outbound,
    IERC20[] memory _inbound,
    AbstractRoutingLogic inboundLogic,
    AbstractRoutingLogic outboundLogic
  )
    internal
    pure
    returns (MangroveAmplifier.FixedBundleParams memory fx, MangroveAmplifier.VariableBundleParams[] memory vr)
  {
    vr = new MangroveAmplifier.VariableBundleParams[](_inbound.length);
    fx.outbound_tkn = _outbound;
    fx.outVolume = 1000 ether;
    if (address(outboundLogic) != address(0)) {
      fx.outboundLogic = outboundLogic;
    }

    for (uint i = 0; i < _inbound.length; i++) {
      vr[i].inbound_tkn = _inbound[i];
      vr[i].tick = TickLib.tickFromVolumes({inboundAmt: 0.5 ether, outboundAmt: 2000 ether});
      vr[i].gasreq = 50_000;
      vr[i].provision = 0.5 ether;
      vr[i].tickSpacing = 1;
      if (address(inboundLogic) != address(0)) {
        vr[i].inboundLogic = inboundLogic;
      }
    }
  }

  function getFirstOfferFromBundle(uint bundleId) internal view returns (OLKey memory key, uint offerId, uint length) {
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId);
    key = OLKey({
      inbound_tkn: address(offers[0].inbound_tkn),
      outbound_tkn: address(outbound),
      tickSpacing: offers[0].tickSpacing
    });
    offerId = offers[0].offerId;
    length = offers.length;
  }

  function getFirstOfferFromBundleAndLockOtherOffers(uint bundleId)
    internal
    returns (OLKey memory key, uint offerId, uint length)
  {
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId);
    key = OLKey({
      inbound_tkn: address(offers[0].inbound_tkn),
      outbound_tkn: address(outbound),
      tickSpacing: offers[0].tickSpacing
    });
    offerId = offers[0].offerId;
    length = offers.length;

    OLKey memory toLock;
    toLock.outbound_tkn = address(outbound);
    toLock.tickSpacing = 1;
    for (uint i = 1; i < offers.length; i++) {
      toLock.inbound_tkn = address(offers[i].inbound_tkn);
      forceLockMarket(mgv, toLock);
      forceLockMarket(mgv, toLock.flipped());
    }
  }

  function unlockAllMarkets(uint bundleId) internal {
    MangroveAmplifier.BundledOffer[] memory offers = mgvAmplifier.offersOf(bundleId);
    OLKey memory toUnlock;
    toUnlock.outbound_tkn = address(outbound);
    toUnlock.tickSpacing = 1;
    for (uint i = 0; i < offers.length; i++) {
      toUnlock.inbound_tkn = address(offers[i].inbound_tkn);
      forceUnlockMarket(mgv, toUnlock);
      forceUnlockMarket(mgv, toUnlock.flipped());
    }
  }

  function testFillForAmplifiedOffer(uint bundleId) internal {
    (OLKey memory key, uint offerId, uint length) = getFirstOfferFromBundle(bundleId);
    (uint makerExecutGas, uint makerPostHookGas) = mock_complete_fill_order(key, offerId);
    console.log("fill makerExecutGas with %s offers: %s", length, makerExecutGas);
    console.log("fill makerPostHookGas with %s offers: %s", length, makerPostHookGas);
  }

  function testPartialFillForAmplifiedOffer(uint bundleId) internal {
    (OLKey memory key, uint offerId, uint length) = getFirstOfferFromBundle(bundleId);
    (uint makerExecutGas, uint makerPostHookGas) = mock_partial_fill_order(key, offerId);
    console.log("partial fill makerExecutGas with %s offers: %s", length, makerExecutGas);
    console.log("partial fill makerPostHookGas with %s offers: %s", length, makerPostHookGas);
  }

  function testPartialFillWithAllOtherMarketLocked(uint bundleId) internal {
    (OLKey memory key, uint offerId, uint length) = getFirstOfferFromBundleAndLockOtherOffers(bundleId);
    (uint makerExecutGas, uint makerPostHookGas) = mock_partial_fill_order(key, offerId);
    console.log("partial fill market lock makerExecutGas with %s offers: %s", length, makerExecutGas);
    console.log("partial fill market lock makerPostHookGas with %s offers: %s", length, makerPostHookGas);
  }

  function test_gasreq_amplified_offer_no_market_lock_3() public {
    testFillForAmplifiedOffer(amplifiedOffer3);
  }

  function test_gasreq_amplified_offer_no_market_lock_5() public {
    testFillForAmplifiedOffer(amplifiedOffer5);
  }

  function test_gasreq_amplified_offer_no_market_lock_8() public {
    testFillForAmplifiedOffer(amplifiedOffer8);
  }

  function test_gasreq_amplified_offer_no_market_lock_10() public {
    testFillForAmplifiedOffer(amplifiedOffer10);
  }

  function test_gasreq_amplified_offer_no_market_lock_30() public {
    testFillForAmplifiedOffer(amplifiedOffer30);
  }

  function test_gasreq_amplified_offer_no_market_lock_50() public {
    testFillForAmplifiedOffer(amplifiedOffer50);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_3() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer3);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_5() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer5);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_8() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer8);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_10() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer10);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_30() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer30);
  }

  function test_gasreq_amplified_offer_no_market_lock_partial_fill_50() public {
    testPartialFillForAmplifiedOffer(amplifiedOffer50);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_3() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer3);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_5() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer5);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_8() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer8);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_10() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer10);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_30() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer30);
  }

  function test_gasreq_amplified_offer_all_other_market_locked_50() public {
    testPartialFillWithAllOtherMarketLocked(amplifiedOffer50);
  }
}

contract MangroveAmplifierGasreqBaseWithPreviousLockTest is MangroveAmplifierGasreqBaseTest {
  function setUpAllAmplifiedOffers() public virtual override {
    amplifiedOffer3 = setUpAmplifiedOffer(3);
    amplifiedOffer5 = setUpAmplifiedOffer(5);
    amplifiedOffer8 = setUpAmplifiedOffer(8);
    amplifiedOffer10 = setUpAmplifiedOffer(10);
    amplifiedOffer30 = setUpAmplifiedOffer(30);
    amplifiedOffer50 = setUpAmplifiedOffer(50);
    makeBundleOfferUseMaxVolume(amplifiedOffer3);
    makeBundleOfferUseMaxVolume(amplifiedOffer5);
    makeBundleOfferUseMaxVolume(amplifiedOffer8);
    makeBundleOfferUseMaxVolume(amplifiedOffer10);
    makeBundleOfferUseMaxVolume(amplifiedOffer30);
    makeBundleOfferUseMaxVolume(amplifiedOffer50);
  }

  function makeBundleOfferUseMaxVolume(uint bundleId) internal {
    (OLKey memory key, uint offerId,) = getFirstOfferFromBundleAndLockOtherOffers(bundleId);
    mock_partial_fill_order(key, offerId);
    unlockAllMarkets(bundleId);
  }
}
