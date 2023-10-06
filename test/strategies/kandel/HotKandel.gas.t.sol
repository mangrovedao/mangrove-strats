// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./abstract/CoreKandel.gas.t.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {Kandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract HotKandelGasTest is CoreKandelGasTest {
  uint constant CROWDYNESS = 0;

  function setUp() public override {
    super.setUp();
    //vm.prank(maker);
    //kdl.retractOffers(4, 5);
    //printOB();
    // making Kandel hot
    vm.prank(taker);
    mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), 0.5 ether, true);
    //printOB();
    vm.prank(taker);
    mgv.marketOrderByTick(lo, Tick.wrap(MAX_TICK), 0.54 ether, false);
    //printOB();
    completeFill_ = 0.108 ether;
    partialFill_ = 0.09 ether;

    if (CROWDYNESS > 0) {
      for (uint index; index < getParams(kdl).pricePoints; index++) {
        densifyMissing(index, CROWDYNESS);
      }
    }
  }
}
