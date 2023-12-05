// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {IOrderLogic} from "@mgv-strats/src/strategies/interfaces/IOrderLogic.sol";
import {IERC20, OLKey, Offer} from "@mgv/src/core/MgvLib.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {MAX_TICK} from "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {OfferGasReqBaseTest} from "@mgv/test/lib/gas/OfferGasReqBase.t.sol";

///@notice Can be used to measure gas overhead of MangroveOrder.
abstract contract MangroveOrderGasreqBaseTest is StratTest, OfferGasReqBaseTest {
  MangroveOrder internal mangroveOrder;
  IOrderLogic.TakerOrderResult internal buyResult;
  IOrderLogic.TakerOrderResult internal sellResult;
  uint GASREQ = 1_000_000;
  uint volume = 2 ether;

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual override {
    super.setUpTokens(baseToken, quoteToken);
    mangroveOrder = new MangroveOrder(IMangrove(payable(mgv)), $(this));
    mangroveOrder.activate(dynamic([IERC20(base), IERC20(quote)]));

    // We approve both base and quote to be able to test both tokens.
    deal($(quote), $(this), 10 ether);
    TransferLib.approveToken(quote, $(mangroveOrder.router()), 10 ether);

    deal($(base), $(this), 10 ether);
    TransferLib.approveToken(base, $(mangroveOrder.router()), 10 ether);

    // A buy
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      olKey: olKey,
      fillOrKill: false,
      fillWants: false,
      fillVolume: 1 ether,
      tick: Tick.wrap(10),
      restingOrder: true,
      expiryDate: block.timestamp + 10000,
      offerId: 0,
      restingOrderGasreq: GASREQ
    });

    buyResult = mangroveOrder.take{value: 1 ether}(buyOrder);
    assertGt(buyResult.offerId, 0, "Resting offer failed to be published on mangrove");
    description = string.concat(description, " - MangroveOrder");
  }

  function test_gas_measurement_market_order() public {
    (IMangrove _mgv,,,) = getStored();
    prankTaker(lo);
    (uint takerGot,, uint bounty,) = _mgv.marketOrderByTick(lo, Tick.wrap(10), volume, true);

    assertGt(takerGot, 0);
    assertEq(bounty, 0);
  }

  function test_gas_measurement_take_overhead() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      olKey: lo,
      fillOrKill: false,
      fillWants: false,
      fillVolume: volume,
      tick: Tick.wrap(10),
      restingOrder: true,
      expiryDate: block.timestamp + 10000,
      offerId: 0,
      restingOrderGasreq: GASREQ // overestimate
    });

    sellResult = mangroveOrder.take{value: 1 ether}(sellOrder);
    assertGt(sellResult.offerId, 0, "Resting offer failed to be published on mangrove");
  }

  receive() external payable {
    // allow mangrove to send native token to test contract
  }
}

contract MangroveOrderGasreqTest_Generic_A_B is MangroveOrderGasreqBaseTest {
  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}
