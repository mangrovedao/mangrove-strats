// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlPopulates is Deployer {
  Kandel public kdl;
  IMangrove MGV;
  IERC20 BASE;
  IERC20 QUOTE;
  MgvReader MGVR;

  function run() public {
    kdl = Kandel(envAddressOrName("KANDEL"));
    innerRun({
      baseDist: vm.envUint("BASEDIST", ","),
      quoteDist: vm.envUint("QUOTEDIST", ","),
      startPopulate: vm.envUint("START"),
      endPopulate: vm.envUint("END"),
      lastBidIndex: vm.envUint("LASTBID"),
      gasprice: vm.envUint("GASPRICE")
    });
  }

  function innerRun(
    uint[] memory baseDist,
    uint[] memory quoteDist,
    uint startPopulate, // start index for the first element of the distribution
    uint endPopulate,
    uint lastBidIndex,
    uint gasprice
  ) public {
    MGV = kdl.MGV();
    MGVR = MgvReader(fork.get("MgvReader"));
    BASE = kdl.BASE();
    QUOTE = kdl.QUOTE();

    require(baseDist.length == quoteDist.length, "Distribution must have same length");
    require(startPopulate <= endPopulate, "start must be lower than end");
    require(baseDist.length == kdl.NSLOTS(), "Distribution length must match Kandel's size");

    uint gasreq = kdl.offerGasreq();
    uint provAsk = MGVR.getProvision(address(BASE), address(QUOTE), gasreq, gasprice);
    uint provBid = MGVR.getProvision(address(QUOTE), address(BASE), gasreq, gasprice);

    prettyLog("Setting distribution on Kandel...");
    vm.broadcast();
    kdl.setDistribution(0, baseDist.length, [baseDist, quoteDist]);

    prettyLog("Evaluating pivots");
    uint[] memory pivotIds = evaluatePivots(
      HeapArgs({
        baseDist: baseDist,
        quoteDist: quoteDist,
        lastBidIndex: int(lastBidIndex) - int(startPopulate),
        provBid: provBid,
        provAsk: provAsk
      })
    );

    prettyLog("Populating Mangrove...");
    vm.broadcast();
    kdl.populate{value: (provAsk + provBid) * (endPopulate - startPopulate)}(
      startPopulate, endPopulate, lastBidIndex, gasprice, pivotIds
    );
  }

  struct HeapArgs {
    uint[] baseDist;
    uint[] quoteDist;
    int lastBidIndex;
    uint provBid;
    uint provAsk;
  }

  function evaluatePivots(HeapArgs memory args) internal returns (uint[] memory pivotIds) {
    pivotIds = new uint[](args.baseDist.length);
    uint gasreq = kdl.offerGasreq();
    uint lastOfferId;

    for (uint i = 0; i < pivotIds.length; i++) {
      bool bidding = args.lastBidIndex >= 0 && i <= uint(args.lastBidIndex);
      (address outbound, address inbound) = bidding ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));

      lastOfferId = MGV.newOffer{value: bidding ? args.provBid : args.provAsk}({
        outbound_tkn: outbound,
        inbound_tkn: inbound,
        wants: bidding ? args.baseDist[i] : args.quoteDist[i],
        gives: bidding ? args.quoteDist[i] : args.baseDist[i],
        gasreq: gasreq,
        gasprice: 0,
        pivotId: lastOfferId
      });
      pivotIds[i] = MGV.offers(outbound, inbound, lastOfferId).next();
      console.log(bidding ? "bid" : "ask", i, pivotIds[i], lastOfferId);
    }
  }
}