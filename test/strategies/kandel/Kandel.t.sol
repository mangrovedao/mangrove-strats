// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MgvStructs, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "mgv_lib/Debug.sol";
import {CoreKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {OfferType} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {LogPriceLib} from "mgv_lib/LogPriceLib.sol";

///@title Tests for Kandel without a router, and router agnostic functions.
contract NoRouterKandelTest is CoreKandelTest {
  function __deployKandel__(address deployer, address reserveId) internal override returns (GeometricKandel kdl_) {
    uint GASREQ = 250_000;
    OLKey memory olKey = OLKey(address(base), address(quote), options.defaultTickScale);

    vm.expectEmit(true, true, true, true);
    emit Mgv(IMangrove($(mgv)));
    vm.expectEmit(true, true, true, true);
    emit OfferListKey(olKey.hash());
    vm.expectEmit(true, true, true, true);
    emit SetGasprice(bufferedGasprice);
    vm.expectEmit(true, true, true, true);
    emit SetGasreq(GASREQ);
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      olKeyBaseQuote: olKey,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      reserveId: reserveId
    });
  }

  function validateDistribution(
    CoreKandel.Distribution memory distribution,
    int baseQuoteLogPriceOffset,
    int baseQuoteLogPriceIndex0,
    OfferType ba,
    uint gives,
    uint dualGives
  ) internal returns (uint zeroes) {
    bool constantGives = gives != type(uint).max;
    for (uint i = 0; i < distribution.indices.length; ++i) {
      uint index = distribution.indices[i];
      assertTrue(!seenOffers[ba][index], string.concat("index ", vm.toString(index), " seen twice"));
      seenOffers[ba][index] = true;

      int absoluteLogPriceAtIndex = baseQuoteLogPriceIndex0 + int(index) * int(baseQuoteLogPriceOffset);
      if (ba == Bid) {
        // console.log("B %s %s %s", distribution.indices[i], vm.toString(distribution.logPriceDist[i]), distribution.givesDist[i]);
        assertEq(distribution.logPriceDist[i], -absoluteLogPriceAtIndex);
      } else {
        // console.log("A %s %s %s", distribution.indices[i], vm.toString(distribution.logPriceDist[i]), distribution.givesDist[i]);
        assertEq(distribution.logPriceDist[i], absoluteLogPriceAtIndex);
      }
      // can be a dual
      if (distribution.givesDist[i] > 0) {
        if (constantGives) {
          assertEq(distribution.givesDist[i], gives, "givesDist should be constant");
        } else {
          uint wants = LogPriceLib.inboundFromOutbound(distribution.logPriceDist[i], distribution.givesDist[i]);
          assertApproxEqRel(wants, dualGives, 1e10, "wants should be approximately constant");
        }
      } else {
        zeroes++;
      }
    }
  }

  mapping(OfferType ba => mapping(uint index => bool seen)) internal seenOffers;

  struct SimpleDistributionHeapArgs {
    int baseQuoteLogPriceIndex0;
    int baseQuoteLogPriceOffset;
    uint firstAskIndex;
    uint askGives;
    uint bidGives;
    uint pricePoints;
    uint spread;
  }

  function test_createDistributionSimple_constantAskBidGives(uint firstAskIndex, uint bidGives, uint askGives) internal {
    test_createDistributionSimple_constantAskBidGives(firstAskIndex, bidGives, askGives, 1);
  }

  function test_createDistributionSimple_constantAskBidGives(
    uint firstAskIndex,
    uint bidGives,
    uint askGives,
    uint spread
  ) internal {
    SimpleDistributionHeapArgs memory args;
    args.firstAskIndex = firstAskIndex;
    args.askGives = askGives;
    args.bidGives = bidGives;
    args.pricePoints = 5;
    args.spread = spread;
    args.baseQuoteLogPriceIndex0 = 500;
    args.baseQuoteLogPriceOffset = 1000;
    test_createDistributionSimple_constantAskBidGives(args, dynamic([uint(2), 4]));
  }

  function test_createDistributionSimple_constantAskBidGives_fuzz(uint seed) public {
    SimpleDistributionHeapArgs memory args;
    uint r = 0;
    args.pricePoints = uint(keccak256(abi.encodePacked(seed, ++r))) % 20;
    if (args.pricePoints < 2) {
      args.pricePoints = 2;
    }
    args.firstAskIndex = uint(keccak256(abi.encodePacked(seed, ++r))) % (args.pricePoints + 1);
    args.spread = uint(keccak256(abi.encodePacked(seed, ++r))) % args.pricePoints;
    if (args.spread == 0) {
      args.spread = 1;
    }
    if (uint(keccak256(abi.encodePacked(seed, ++r))) % 2 == 0) {
      args.askGives = 1 ether;
      if (uint(keccak256(abi.encodePacked(seed, ++r))) % 2 == 0) {
        args.bidGives = 3 ether;
      } else {
        args.bidGives = type(uint).max;
      }
    } else {
      args.askGives = type(uint).max;
      args.bidGives = 2 ether;
    }
    args.baseQuoteLogPriceIndex0 = 500;
    args.baseQuoteLogPriceOffset = 1000;
    uint[] memory cuts = new uint[](uint(keccak256(abi.encodePacked(seed, ++r))) % args.pricePoints);
    if (cuts.length == 0) {
      cuts = new uint[](1);
    }
    for (uint i = 0; i < cuts.length; ++i) {
      cuts[i] =
        (i > 0 ? cuts[i - 1] : 0) + (args.pricePoints / cuts.length + uint(keccak256(abi.encodePacked(seed, ++r))) % 3);
      if (cuts[i] > args.pricePoints) {
        cuts[i] = args.pricePoints;
      }
    }
    test_createDistributionSimple_constantAskBidGives(args, cuts);
  }

  function test_createDistributionSimple_constantAskBidGives(SimpleDistributionHeapArgs memory args, uint[] memory cuts)
    internal
  {
    CoreKandel.Distribution[] memory bidDistribution = new CoreKandel.Distribution[](cuts.length+1);
    CoreKandel.Distribution[] memory askDistribution = new CoreKandel.Distribution[](cuts.length+1);

    for (uint i = 0; i < cuts.length; i++) {
      (bidDistribution[i], askDistribution[i]) = kdl.createDistribution({
        from: i > 0 ? cuts[i - 1] : 0,
        to: i < cuts.length - 1 ? cuts[i] : args.pricePoints,
        baseQuoteLogPriceIndex0: args.baseQuoteLogPriceIndex0,
        _baseQuoteLogPriceOffset: args.baseQuoteLogPriceOffset,
        firstAskIndex: args.firstAskIndex,
        askGives: args.askGives,
        bidGives: args.bidGives,
        pricePoints: args.pricePoints,
        spread: args.spread
      });
    }

    uint totalIndices = 0;
    uint totalZeros = 0;
    for (uint i = 0; i < bidDistribution.length; i++) {
      totalIndices += bidDistribution[i].indices.length + askDistribution[i].indices.length;
      totalZeros += validateDistribution(
        bidDistribution[i],
        args.baseQuoteLogPriceOffset,
        args.baseQuoteLogPriceIndex0,
        OfferType.Bid,
        args.bidGives,
        args.askGives
      );
      totalZeros += validateDistribution(
        askDistribution[i],
        args.baseQuoteLogPriceOffset,
        args.baseQuoteLogPriceIndex0,
        OfferType.Ask,
        args.askGives,
        args.bidGives
      );
    }

    for (uint i = 0; i < args.pricePoints; ++i) {
      if (i < args.spread) {
        if (i < args.pricePoints - args.spread) {
          assertTrue(seenOffers[Bid][i], string.concat("bid not seen at index ", vm.toString(i)));
        } else {
          assertFalse(
            seenOffers[Bid][i],
            string.concat("bid seen too close to end for dual ask to be possible at index ", vm.toString(i))
          );
        }
        assertFalse(seenOffers[Ask][i], string.concat("ask seen at index in spread hole at low index ", vm.toString(i)));
      } else if (i >= args.pricePoints - args.spread) {
        assertFalse(
          seenOffers[Bid][i], string.concat("bid seen at index in spread hole at high index ", vm.toString(i))
        );
        assertTrue(seenOffers[Ask][i], string.concat("ask not seen at index ", vm.toString(i)));
      } else {
        assertTrue(seenOffers[Bid][i], string.concat("bid not seen at index ", vm.toString(i)));
        assertTrue(seenOffers[Ask][i], string.concat("ask not seen at index ", vm.toString(i)));
      }
      // Reset to allow multiple tests in one function.
      seenOffers[Bid][i] = false;
      seenOffers[Ask][i] = false;
    }

    assertEq(totalIndices, 2 * (args.pricePoints - args.spread), "an offer and its dual, except near end");
    if (args.bidGives != 0 && args.askGives != 0) {
      assertEq(totalZeros, args.pricePoints - args.spread);
    }
  }

  function test_createDistribution_constantAskGives() public {
    test_createDistributionSimple_constantAskBidGives(0, type(uint).max, 2 ether);
    test_createDistributionSimple_constantAskBidGives(1, type(uint).max, 2 ether);
    test_createDistributionSimple_constantAskBidGives(2, type(uint).max, 2 ether);
    test_createDistributionSimple_constantAskBidGives(3, type(uint).max, 2 ether);
    test_createDistributionSimple_constantAskBidGives(4, type(uint).max, 2 ether);
    test_createDistributionSimple_constantAskBidGives(5, type(uint).max, 2 ether, 4);
    test_createDistributionSimple_constantAskBidGives(0, type(uint).max, 2 ether, 4);
    test_createDistributionSimple_constantAskBidGives(3, type(uint).max, 2 ether, 2);
    test_createDistributionSimple_constantAskBidGives(2, type(uint).max, 2 ether, 2);
  }

  function test_createDistribution_constantBidGives() public {
    test_createDistributionSimple_constantAskBidGives(0, 2 ether, type(uint).max);
    test_createDistributionSimple_constantAskBidGives(1, 2 ether, type(uint).max);
    test_createDistributionSimple_constantAskBidGives(2, 2 ether, type(uint).max);
    test_createDistributionSimple_constantAskBidGives(3, 2 ether, type(uint).max);
  }

  function test_createDistribution_constantGives() public {
    test_createDistributionSimple_constantAskBidGives(1, 2 ether, 4 ether);
  }

  function test_createDistribution_constantGives_0() public {
    test_createDistributionSimple_constantAskBidGives(2, 0, 0);
  }

  function test_createDistribution_bothVariable() public {
    vm.expectRevert("Kandel/bothGivesVariable");
    kdl.createDistribution({
      from: 0,
      to: 2,
      baseQuoteLogPriceIndex0: 0,
      _baseQuoteLogPriceOffset: 0,
      firstAskIndex: 1,
      askGives: type(uint).max,
      bidGives: type(uint).max,
      pricePoints: 10,
      spread: 1
    });
  }
}
