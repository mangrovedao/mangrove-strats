// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferGasBaseBaseTest} from "@mgv/test/lib/gas/OfferGasBaseBase.t.sol";

///@notice For comparison to subtract from gasreq tests.
contract OfferGasBaseTest_Polygon_WETH_DAI is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}
