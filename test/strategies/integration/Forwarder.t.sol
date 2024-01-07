// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, SimpleRouter, RL} from "@mgv-strats/src/strategies/routers/SimpleRouter.sol";
import {OfferLogicTest} from "./abstract/OfferLogic.t.sol";
import {
  IForwarder,
  IMangrove,
  IERC20,
  MangroveOffer,
  RouterProxy
} from "@mgv-strats/src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ForwarderTester, ITesterContract} from "@mgv-strats/test/lib/agents/ForwarderTester.sol";
import {MgvLib} from "@mgv/src/core/MgvLib.sol";
import {TestSender} from "@mgv/test/lib/agents/TestSender.sol";
import "@mgv/lib/Debug.sol";

contract ForwarderTest is OfferLogicTest {
  ForwarderTester forwarder;

  function setUp() public virtual override {
    vm.deal(deployer, 10 ether);
    super.setUp();
  }

  event NewOwnedOffer(bytes32 indexed olKeyHash, uint indexed offerId, address indexed owner);

  function setupMakerContract() internal virtual override {
    vm.startPrank(deployer);
    forwarder = new ForwarderTester({mgv: IMangrove($(mgv)), routerImplementation: new SimpleRouter()});
    vm.stopPrank();
    gasreq = 160_000;
    vm.deal(deployer, 10 ether);

    vm.prank(deployer);
    owner = payable(address(new TestSender()));
    vm.deal(owner, 10 ether);

    makerContract = ITesterContract(address(forwarder)); // to use for all non `IForwarder` specific tests.
    // making sure owner has a router that is bound to makerContract
    (RouterProxy ownerProxy,) = forwarder.ROUTER_FACTORY().instantiate(owner, forwarder.ROUTER_IMPLEMENTATION());
    vm.startPrank(owner);
    AbstractRouter(address(ownerProxy)).bind(address(makerContract));
    weth.approve(address(ownerProxy), type(uint).max);
    usdc.approve(address(ownerProxy), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  function test_derived_gasprice_is_accurate_enough(uint fund) public {
    vm.assume(fund >= reader.getProvision(olKey, gasreq, 0));
    vm.assume(fund < 5 ether); // too high provision would yield a gasprice overflow
    uint contractOldBalance = mgv.balanceOf(address(makerContract));
    vm.prank(owner);
    uint offerId =
      makerContract.newOfferByVolume{value: fund}({olKey: olKey, wants: 2000 * 10 ** 6, gives: 1 ether, gasreq: gasreq});
    uint derived_gp = mgv.offerDetails(olKey, offerId).gasprice();
    uint gasbase = mgv.offerDetails(olKey, offerId).offer_gasbase();
    uint locked = derived_gp * (gasbase + gasreq) * 1e6;
    uint leftover = fund - locked;
    assertEq(mgv.balanceOf(address(makerContract)), contractOldBalance + leftover, "Invalid contract balance");
    console.log("counterexample:", locked, fund, (locked * 1000) / fund);
    assertTrue((locked * 10) / fund >= 9, "rounding exceeds admissible error");
  }

  function test_updateOffer_with_funds_updates_gasprice() public {
    vm.prank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    uint old_gasprice = mgv.offerDetails(olKey, offerId).gasprice();
    vm.prank(owner);
    makerContract.updateOfferByVolume{value: 0.2 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      offerId: offerId,
      gasreq: gasreq
    });
    assertTrue(old_gasprice < mgv.offerDetails(olKey, offerId).gasprice(), "Gasprice not updated as expected");
  }

  function test_maker_ownership() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    assertEq(forwarder.ownerOf(olKey.hash(), offerId), owner, "Invalid maker ownership relation");
  }

  function test_NewOwnedOffer_logging() public {
    (, Local local) = mgv.config(olKey);
    uint next_id = local.last() + 1;
    vm.expectEmit(true, true, true, false, address(forwarder));
    emit NewOwnedOffer(olKey.hash(), next_id, owner);

    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    assertEq(next_id, offerId, "Unexpected offer id");
  }

  function test_provision_too_high_reverts() public {
    vm.deal(owner, 30 ether);
    vm.expectRevert("Forwarder/provisionTooHigh");
    vm.prank(owner);
    makerContract.newOfferByVolume{value: 30 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
  }

  function test_updateOffer_with_no_funds_preserves_gasprice() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
    OfferDetail detail = mgv.offerDetails(olKey, offerId);
    uint old_gasprice = detail.gasprice();

    vm.startPrank(owner);
    makerContract.updateOfferByVolume({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      offerId: offerId,
      gasreq: gasreq
    });
    vm.stopPrank();
    detail = mgv.offerDetails(olKey, offerId);
    assertEq(old_gasprice, detail.gasprice(), "Gas price was changed");
  }

  function test_updateOffer_with_funds_increases_gasprice() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
    OfferDetail detail = mgv.offerDetails(olKey, offerId);
    uint old_gasprice = detail.gasprice();
    vm.startPrank(owner);
    makerContract.updateOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      offerId: offerId,
      gasreq: gasreq
    });
    vm.stopPrank();
    detail = mgv.offerDetails(olKey, offerId);
    assertTrue(old_gasprice < detail.gasprice(), "Gas price was not increased");
  }

  function test_different_maker_can_post_offers() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
    address new_maker = freshAddress("New maker");
    vm.deal(new_maker, 1 ether);

    vm.startPrank(new_maker);
    uint offerId_ = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    vm.stopPrank();
    assertEq(forwarder.ownerOf(olKey.hash(), offerId_), new_maker, "Incorrect maker");
    assertEq(forwarder.ownerOf(olKey.hash(), offerId), owner, "Incorrect maker");
  }

  // Forwarder call `put` during `makerExecute` this test makes it fail.
  function test_put_fail_reverts_with_expected_reason() public {
    MgvLib.SingleOrder memory order;
    vm.startPrank(owner);
    uint offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: gasreq
    });
    usdc.approve($(makerContract.router(owner)), 0);
    vm.stopPrank();

    order.olKey = olKey;
    order.takerGives = 10 ** 6;
    order.offerId = offerId;
    vm.expectRevert("mgvOffer/abort/putFailed");
    vm.prank($(mgv));
    makerContract.makerExecute(order);
  }

  function test_failed_offer_handles_residual_provision(uint96 prov) public {
    vm.assume(prov > 0.04 ether);
    vm.assume(prov <= 10 ether);
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.prank(owner);
    uint offerId =
      makerContract.newOfferByVolume{value: prov}({olKey: olKey, wants: 2000 * 10 ** 6, gives: 1 ether, gasreq: gasreq});
    uint old_provision = makerContract.provisionOf(olKey, offerId);
    assertEq(old_provision, prov, "Invalid provision");

    result.mgvData = "anythingButSuccess";
    result.makerData = "failReason";
    order.offerId = offerId;
    order.olKey = olKey;
    order.offer = mgv.offers(olKey, offerId);
    order.offerDetail = mgv.offerDetails(olKey, offerId);
    // this should reach the posthookFallback and computes released provision, assuming offer has failed for half gasreq
    // as a result the amount of provision that can be redeemed by retracting offerId should increase.
    vm.startPrank($(mgv));
    makerContract.makerPosthook{gas: gasreq / 2}(order, result);
    vm.stopPrank();
    uint new_provision = makerContract.provisionOf(olKey, offerId);
    assertTrue(new_provision > old_provision, "fallback was not reached");
  }
}
