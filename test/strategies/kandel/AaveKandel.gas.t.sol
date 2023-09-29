// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {CoreKandelGasTest} from "./abstract/CoreKandel.gas.t.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {AaveKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {AavePooledRouter} from "@mgv-strats/src/strategies/routers/integrations/AavePooledRouter.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";

contract AaveKandelGasTest is CoreKandelGasTest {
  function __deployKandel__(address deployer, address reserveId) internal override returns (GeometricKandel kdl_) {
    //FIXME: Measure
    uint GASREQ = 360_000;
    uint ROUTER_GASREQ = 280_000;
    vm.startPrank(deployer);
    kdl_ = new AaveKandel({
      mgv: mgv,
      olKeyBaseQuote: olKey,
      gasreq: GASREQ,
      reserveId: reserveId
    });
    AavePooledRouter router = new AavePooledRouter(fork.get("Aave"), ROUTER_GASREQ);
    router.setAaveManager(msg.sender);
    router.bind(address(kdl_));
    AaveKandel(payable(kdl_)).initialize(router);
    vm.stopPrank();
  }

  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.08 ether;
  }
}
