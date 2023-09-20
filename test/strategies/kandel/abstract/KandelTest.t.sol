// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs, MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {OfferType} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {
  CoreKandel, TransferLib
} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {console} from "forge-std/Test.sol";
import {StratTest, MangroveTest} from "mgv_strat_test/lib/StratTest.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {AbstractRouter} from "mgv_strat_src/strategies/routers/AbstractRouter.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";
import {toFixed} from "mgv_lib/Test2.sol";
import {LogPriceLib} from "mgv_lib/LogPriceLib.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";

abstract contract KandelTest is StratTest {
  address payable maker;
  address payable taker;
  GeometricKandel kdl;
  uint8 constant STEP = 1;
  uint initQuote;
  uint initBase = 0.1 ether;
  uint globalGasprice;
  uint bufferedGasprice;
  // A ratio of ~108% can be converted to a log price step of ~769 via
  // uint logPriceOffset = LogPriceConversionLib.logPriceFromVolumes(1 ether * uint(108000) / (100000), 1 ether);
  uint logPriceOffset = 769;
  // and vice versa with
  // ratio = uint24(LogPriceLib.inboundFromOutbound(logPriceOffset, 1 ether) * 100000 / LogPriceLib.inboundFromOutbound(0, 1 ether)

  OfferType constant Ask = OfferType.Ask;
  OfferType constant Bid = OfferType.Bid;

  event Mgv(IMangrove mgv);
  event OfferListKey(bytes32 olKeyHash);
  event NewKandel(address indexed owner, bytes32 indexed olKeyHash, address kandel);
  event SetSpread(uint value);
  event SetLength(uint value);
  event SetGasreq(uint value);
  event Credit(IERC20 indexed token, uint amount);
  event Debit(IERC20 indexed token, uint amount);
  event PopulateStart();
  event PopulateEnd();
  event RetractStart();
  event RetractEnd();
  event LogIncident(bytes32 indexed olKeyHash, uint indexed offerId, bytes32 makerData, bytes32 mgvData);
  event SetBaseQuoteLogPriceOffset(uint value);

  // sets environment default is local node with fake base and quote
  function __setForkEnvironment__() internal virtual {
    // no fork
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;
    options.gasprice = 40;

    MangroveTest.setUp();
  }

  // defines how to deploy a Kandel strat
  function __deployKandel__(address deployer, address reserveId) internal virtual returns (GeometricKandel kdl_);

  function precisionForAssert() internal pure virtual returns (uint) {
    return 0;
  }

  function getAbiPath() internal pure virtual returns (string memory) {
    return "/out/Kandel.sol/Kandel.json";
  }

  function setUp() public virtual override {
    /// sets base, quote, opens a market (base,quote) on Mangrove
    __setForkEnvironment__();
    require(reader != MgvReader(address(0)), "Could not get reader");

    initQuote = cash(quote, 100); // quote given/wanted at index from

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(base), taker, cash(base, 50));
    deal($(quote), taker, cash(quote, 70_000));

    // taker approves mangrove to be able to take offers
    vm.prank(taker);
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    vm.prank(taker);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);

    // deploy and activate
    (MgvStructs.GlobalPacked global,) = mgv.config(OLKey(address(0), address(0), 0));
    globalGasprice = global.gasprice();
    bufferedGasprice = globalGasprice * 10; // covering 10 times Mangrove's gasprice at deploy time

    kdl = __deployKandel__(maker, maker);

    // funding Kandel on Mangrove
    uint provAsk = reader.getProvision(olKey, kdl.offerGasreq(), bufferedGasprice);
    uint provBid = reader.getProvision(lo, kdl.offerGasreq(), bufferedGasprice);
    deal(maker, (provAsk + provBid) * 10 ether);

    // maker approves Kandel to be able to deposit funds on it
    vm.prank(maker);
    TransferLib.approveToken(base, address(kdl), type(uint).max);
    vm.prank(maker);
    TransferLib.approveToken(quote, address(kdl), type(uint).max);

    uint firstAskIndex = 5;

    GeometricKandel.Params memory params;
    params.spread = STEP;
    params.pricePoints = 10;
    int baseQuoteLogPriceIndex0 = LogPriceConversionLib.logPriceFromVolumes(initQuote, initBase);

    vm.prank(maker);
    kdl.populateFromOffset{value: (provAsk + provBid) * 10}({
      from: 0,
      to: 5,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      _baseQuoteLogPriceOffset: logPriceOffset,
      firstAskIndex: firstAskIndex,
      bidGives: type(uint).max,
      askGives: initBase,
      parameters: params,
      baseAmount: 0,
      quoteAmount: 0
    });
    vm.prank(maker);
    kdl.populateChunkFromOffset({
      from: 5,
      to: 10,
      baseQuoteLogPriceIndex0: baseQuoteLogPriceIndex0,
      firstAskIndex: firstAskIndex,
      bidGives: type(uint).max,
      askGives: initBase
    });
    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);

    expectFrom($(kdl));
    emit Credit(base, pendingBase);
    expectFrom($(kdl));
    emit Credit(quote, pendingQuote);
    vm.prank(maker);
    kdl.depositFunds(pendingBase, pendingQuote);
  }

  function buyFromBestAs(address taker_, uint amount) public returns (uint, uint, uint, uint) {
    (, MgvStructs.OfferPacked best) = getBestOffers();
    vm.prank(taker_);
    return mgv.marketOrderByLogPrice(olKey, best.logPrice(), best.gives() >= amount ? amount : best.gives(), true);
  }

  function sellToBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint) {
    (MgvStructs.OfferPacked best,) = getBestOffers();
    vm.prank(taker_);
    return mgv.marketOrderByLogPrice(lo, best.logPrice(), best.wants() >= amount ? amount : best.wants(), false);
  }

  function cleanBuyBestAs(address taker_, uint amount) public returns (uint, uint) {
    (, MgvStructs.OfferPacked best) = getBestOffers();
    uint offerId = mgv.best(olKey);
    vm.prank(taker_);
    return mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, best.logPrice(), 1_000_000, amount)), taker_
    );
  }

  function cleanSellBestAs(address taker_, uint amount) internal returns (uint, uint) {
    (MgvStructs.OfferPacked best,) = getBestOffers();
    uint offerId = mgv.best(lo);
    vm.prank(taker_);
    return mgv.cleanByImpersonation(
      lo, wrap_dynamic(MgvLib.CleanTarget(offerId, best.logPrice(), 1_000_000, amount)), taker_
    );
  }

  function getParams(GeometricKandel aKandel) internal view returns (GeometricKandel.Params memory params) {
    (uint16 gasprice, uint24 gasreq, uint104 spread, uint112 pricePoints) = aKandel.params();

    params.gasprice = gasprice;
    params.gasreq = gasreq;
    params.spread = spread;
    params.pricePoints = pricePoints;
  }

  enum OfferStatus {
    Dead, // both dead
    Bid, // live bid
    Ask, // live ask
    Crossed // both live
  }

  struct IndexStatus {
    MgvStructs.OfferPacked bid;
    MgvStructs.OfferPacked ask;
    OfferStatus status;
  }

  function getStatus(uint index) internal view returns (IndexStatus memory idx) {
    idx.bid = kdl.getOffer(Bid, index);
    idx.ask = kdl.getOffer(Ask, index);
    if (idx.bid.gives() > 0 && idx.ask.gives() > 0) {
      idx.status = OfferStatus.Crossed;
    } else {
      if (idx.bid.gives() > 0) {
        idx.status = OfferStatus.Bid;
      } else {
        if (idx.ask.gives() > 0) {
          idx.status = OfferStatus.Ask;
        } else {
          idx.status = OfferStatus.Dead;
        }
      }
    }
  }

  ///@notice asserts status of index.
  function assertStatus(uint index, OfferStatus status) internal {
    assertStatus(index, status, type(uint).max, type(uint).max);
  }

  ///@notice asserts status of index and verifies price based on geometric progressing quote.
  function assertStatus(uint index, OfferStatus status, uint q, uint b) internal {
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index);
    bool bidLive = bid.isLive();
    bool askLive = ask.isLive();

    if (status == OfferStatus.Dead) {
      assertTrue(!bidLive && !askLive, "offer at index is live");
    } else {
      if (status == OfferStatus.Bid) {
        assertTrue(bidLive && !askLive, "Kandel not bidding at index");
        if (q != type(uint).max) {
          assertApproxEqRel(
            bid.gives() * b, q * bid.wants(), 1e14, "Bid price does not follow distribution within 0.00001%"
          );
        }
      } else {
        if (status == OfferStatus.Ask) {
          assertTrue(!bidLive && askLive, "Kandel is not asking at index");
          if (q != type(uint).max) {
            assertApproxEqRel(
              ask.wants() * b, q * ask.gives(), 1e14, "Ask price does not follow distribution within 0.00001%"
            );
          }
        } else {
          assertTrue(bidLive && askLive, "Kandel is not crossed at index");
        }
      }
    }
  }

  function assertStatus(
    uint[] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
  ) internal {
    assertStatus(offerStatuses, initQuote, initBase);
  }

  function assertStatus(
    uint[] memory offerStatuses, // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
    uint q, // initial quote at first price point, type(uint).max to ignore in verification
    uint b // initial base at first price point, type(uint).max to ignore in verification
  ) internal {
    assertStatus(offerStatuses, q, b, logPriceOffset);
  }

  function assertStatus(
    uint[] memory offerStatuses, // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
    uint q, // initial quote at first price point, type(uint).max to ignore in verification
    uint b, // initial base at first price point, type(uint).max to ignore in verification
    uint _logPriceOffset
  ) internal {
    uint expectedBids = 0;
    uint expectedAsks = 0;
    for (uint i = 0; i < offerStatuses.length; i++) {
      // `price = quote / initBase` used in assertApproxEqRel below
      OfferStatus offerStatus = OfferStatus(offerStatuses[i]);
      assertStatus(i, offerStatus, q, b);
      if (q != type(uint).max) {
        q = (q * LogPriceLib.inboundFromOutbound(int(_logPriceOffset), 1 ether)) / 1 ether;
      }
      if (offerStatus == OfferStatus.Ask) {
        expectedAsks++;
      } else if (offerStatus == OfferStatus.Bid) {
        expectedBids++;
      } else if (offerStatus == OfferStatus.Crossed) {
        expectedAsks++;
        expectedBids++;
      }
    }

    (, uint[] memory bidIds,,) = reader.offerList(lo, 0, 1000);
    (, uint[] memory askIds,,) = reader.offerList(olKey, 0, 1000);
    assertEq(expectedBids, bidIds.length, "Unexpected number of live bids on book");
    assertEq(expectedAsks, askIds.length, "Unexpected number of live asks on book");
  }

  enum ExpectedChange {
    Same,
    Increase,
    Decrease
  }

  function assertChange(ExpectedChange expectedChange, uint expected, uint actual, string memory descriptor) internal {
    if (expectedChange == ExpectedChange.Same) {
      assertApproxEqRel(expected, actual, 1e15, string.concat(descriptor, " should be unchanged to within 0.1%"));
    } else if (expectedChange == ExpectedChange.Decrease) {
      assertGt(expected, actual, string.concat(descriptor, " should have decreased"));
    } else {
      assertLt(expected, actual, string.concat(descriptor, " should have increased"));
    }
  }

  function printOB() internal view {
    printOrderBook(olKey);
    printOrderBook(lo);
    uint pendingBase = uint(kdl.pending(Ask));
    uint pendingQuote = uint(kdl.pending(Bid));

    console.log("-------", toFixed(pendingBase, 18), toFixed(pendingQuote, 6), "-------");
  }

  function emptyDist() internal pure returns (CoreKandel.Distribution memory) {
    CoreKandel.Distribution memory emptyDist_;
    return emptyDist_;
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint base,
    uint quote,
    uint firstAskIndex,
    bytes memory expectRevert
  ) internal {
    GeometricKandel.Params memory params = getParams(kdl);
    populateSingle(kandel, index, base, quote, firstAskIndex, params.pricePoints, params.spread, expectRevert);
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint base,
    uint quote,
    uint firstAskIndex,
    uint pricePoints,
    uint spread,
    bytes memory expectRevert
  ) internal {
    CoreKandel.Distribution memory distribution;
    distribution.indices = new uint[](1);
    distribution.logPriceDist = new int[](1);
    distribution.givesDist = new uint[](1);

    int logPrice = index < firstAskIndex
      ? LogPriceConversionLib.logPriceFromVolumes(base, quote)
      : LogPriceConversionLib.logPriceFromVolumes(quote, base);
    if (base == 0 || quote == 0) {
      // logPrice API should set a meaningful log price, for now, just set price to 1.
      logPrice = 0;
    }
    uint gives = index < firstAskIndex ? quote : base;

    distribution.indices[0] = index;
    distribution.logPriceDist[0] = logPrice;
    distribution.givesDist[0] = gives;
    vm.prank(maker);
    if (expectRevert.length > 0) {
      vm.expectRevert(expectRevert);
    }
    GeometricKandel.Params memory params;
    params.pricePoints = uint112(pricePoints);
    params.spread = uint104(spread);

    kandel.populate{value: 0.1 ether}(
      index < firstAskIndex ? distribution : emptyDist(),
      index < firstAskIndex ? emptyDist() : distribution,
      params,
      0,
      0
    );
  }

  function populateConstantDistribution(uint size) internal returns (uint baseAmount, uint quoteAmount) {
    GeometricKandel.Params memory params = getParams(kdl);
    uint firstAskIndex = size / 2;
    (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution) = kdl
      .createDistribution(
      0,
      size,
      LogPriceConversionLib.logPriceFromVolumes(initQuote, initBase),
      0,
      firstAskIndex,
      1500 * 10 ** 6,
      1 ether,
      size,
      params.spread
    );

    vm.prank(maker);
    kdl.populate{value: maker.balance}(bidDistribution, askDistribution, params, 0, 0);

    for (uint i; i < bidDistribution.indices.length; i++) {
      quoteAmount += bidDistribution.givesDist[i];
    }
    for (uint i; i < askDistribution.indices.length; i++) {
      baseAmount += askDistribution.givesDist[i];
    }
  }

  function getBestOffers() internal view returns (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) {
    uint bestAskId = mgv.best(olKey);
    uint bestBidId = mgv.best(lo);
    bestBid = mgv.offers(lo, bestBidId);
    bestAsk = mgv.offers(olKey, bestAskId);
  }

  function getMidPrice() internal view returns (uint midWants, uint midGives) {
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    midWants = bestBid.wants() * bestAsk.wants() + bestBid.gives() * bestAsk.gives();
    midGives = bestAsk.gives() * bestBid.wants() * 2;
  }

  function getDeadOffers(uint midGives, uint midWants)
    internal
    view
    returns (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids)
  {
    GeometricKandel.Params memory params = getParams(kdl);

    uint[] memory indicesPre = new uint[](params.pricePoints);
    quoteAtIndex = new uint[](params.pricePoints);
    numBids = 0;

    uint quote = initQuote;

    uint firstAskIndex = type(uint).max;
    for (uint i = 0; i < params.pricePoints; i++) {
      // Decide on bid/ask via mid
      OfferType ba = quote * midGives <= initBase * midWants ? Bid : Ask;
      if (ba == Ask && firstAskIndex == type(uint).max) {
        firstAskIndex = i;
      }
      quoteAtIndex[i] = quote;
      quote = (quote * LogPriceLib.inboundFromOutbound(int(uint(logPriceOffset)), 1 ether)) / 1 ether;
    }

    // find missing offers
    uint numDead = 0;
    for (uint i = 0; i < params.pricePoints; i++) {
      MgvStructs.OfferPacked offer = kdl.getOffer(i < firstAskIndex ? Bid : Ask, i);
      if (!offer.isLive()) {
        bool unexpectedDead = false;
        if (i < firstAskIndex) {
          if (i < firstAskIndex - params.spread / 2 - params.spread % 2) {
            numBids++;
            unexpectedDead = true;
          }
        } else {
          if (i >= firstAskIndex + params.spread / 2) {
            unexpectedDead = true;
          }
        }
        if (unexpectedDead) {
          indicesPre[numDead] = i;
          numDead++;
        }
      }
    }

    // truncate indices - cannot do push to memory array
    indices = new uint[](numDead);
    for (uint i = 0; i < numDead; i++) {
      indices[i] = indicesPre[i];
    }
  }
}
