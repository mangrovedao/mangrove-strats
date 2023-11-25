// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferLogicTest, TestSender, IMangrove, ITesterContract, MangroveOffer} from "./OfferLogic.t.sol";
import {ForwarderTester} from "@mgv-strats/test/lib/agents/ForwarderTester.sol";
import {SmartRouter, AbstractRoutingLogic, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {SimpleAaveLogic, IPoolAddressesProvider} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";

import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {AllMethodIdentifiersTest} from "@mgv/test/lib/AllMethodIdentifiersTest.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import "@mgv/lib/Debug.sol";

contract SmartRouterTest is OfferLogicTest {
  ForwarderTester forwarder; // basic forwarder strat
  SmartRouter ownerRouter; // router implementation

  // aave logic
  SimpleAaveLogic aaveLogic;

  event SetRouteLogic(IERC20 indexed token, bytes32 indexed olKeyHash, uint offerId, AbstractRoutingLogic logic);

  function setUp() public override {
    fork = new PinnedPolygonFork(39880000);
    super.setUp();
  }

  function setupMakerContract() internal override {
    vm.startPrank(deployer);
    forwarder = new ForwarderTester(mgv, new SmartRouter());
    vm.stopPrank();
    makerContract = ITesterContract(address(forwarder)); // for OfferLogic tests
    aaveLogic = new SimpleAaveLogic(IPoolAddressesProvider(fork.get("AaveAddressProvider")), 2);
    gasreq = 450_000;
  }

  function fundStrat() internal override {
    deal(address(weth), owner, 10 ether);
    deal(address(usdc), owner, 10_000 * 10 ** 6);
    vm.deal(owner, 10 ether);

    ownerRouter = SmartRouter(address(activateOwnerRouter(weth, MangroveOffer(payable(address(makerContract))), owner)));
    activateOwnerRouter(usdc, MangroveOffer(payable(address(makerContract))), owner);
    vm.startPrank(owner);
    // approving aave logic to pull weth from the owner's wallet
    weth.approve(address(aaveLogic.POOL()), 10 ether);
    // depositing 10 weth in aave
    aaveLogic.POOL().supply(address(weth), 10 ether, owner, 0);
    vm.stopPrank();
  }

  function performTrade(bool success)
    internal
    override
    returns (uint takerGot, uint takerGave, uint bounty, uint fee, uint offerId)
  {
    vm.startPrank(owner);
    // ask 2000 USDC for 1 weth
    offerId = makerContract.newOfferByVolume{value: 0.1 ether}({
      olKey: olKey,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: gasreq
    });
    // setting pull logic for the offer to use aave
    ownerRouter.setLogic(
      RL.RoutingOrder({token: weth, offerId: offerId, olKeyHash: olKey.hash(), fundOwner: owner, amount: 0}), aaveLogic
    );
    IERC20 aWeth = aaveLogic.overlying(weth);
    // allowing aave logic to pull aWeth from the owner's wallet
    activateOwnerRouter(aWeth, MangroveOffer(payable(address(makerContract))), owner);
    // using simple logic for push so leaving it as is
    vm.stopPrank();

    // expecting that nothing should go wrong during offer logic's execution
    vm.expectEmit(true, true, true, false, address(mgv));
    emit OfferSuccess({olKeyHash: olKey.hash(), taker: taker, id: offerId, takerWants: 0, takerGives: 0});

    vm.startPrank(taker);
    (takerGot, takerGave, bounty, fee) =
      mgv.marketOrderByVolume({olKey: olKey, takerWants: 0.5 ether, takerGives: cash(usdc, 1000), fillWants: true});
    vm.stopPrank();
    assertTrue(!success || (bounty == 0 && takerGot > 0), "unexpected trade result");
  }

  function test_owner_balance_is_updated_when_trade_succeeds() public override {
    uint balWethBefore = aaveLogic.balanceLogic(weth, owner); // balance on aave
    uint balUsdBefore = usdc.balanceOf(owner); // balance on owner's wallet

    // taker wants 0.5 weth for at most 1000 usdc
    (uint takerGot, uint takerGave, uint bounty, uint fee, uint offerId) = performTrade(true);
    AbstractRoutingLogic logic = ownerRouter.getLogic(
      RL.RoutingOrder({token: weth, offerId: offerId, olKeyHash: olKey.hash(), fundOwner: owner, amount: 0})
    );
    assertEq(address(logic), address(aaveLogic), "unexpected logic address");

    assertTrue(bounty == 0 && takerGot > 0, "trade failed");
    uint balWethAfter = aaveLogic.balanceLogic(weth, owner);
    uint balUsdAfter = usdc.balanceOf(owner);
    assertEq(balWethAfter, balWethBefore - takerGot - fee, "unexpected owner weth balance");
    assertEq(balUsdAfter, balUsdBefore + takerGave, "unexpected owner usd balance");
  }

  function test_setLogic_logs() public {
    vm.expectRevert("AccessControlled/Invalid");
    ownerRouter.setLogic(
      RL.createOrder({token: weth, amount: type(uint).max, fundOwner: owner}), AbstractRoutingLogic(address(0))
    );

    vm.expectEmit();
    emit SetRouteLogic({token: weth, olKeyHash: bytes32(0), offerId: 0, logic: AbstractRoutingLogic(address(0))});

    // owner can set logic
    vm.prank(owner);
    ownerRouter.setLogic(
      RL.createOrder({token: weth, amount: type(uint).max, fundOwner: owner}), AbstractRoutingLogic(address(0))
    );

    vm.expectEmit();
    emit SetRouteLogic({token: weth, olKeyHash: bytes32(0), offerId: 0, logic: AbstractRoutingLogic(address(0))});

    // bound maker contract can set logic
    vm.prank(address(makerContract));
    ownerRouter.setLogic(
      RL.createOrder({token: weth, amount: type(uint).max, fundOwner: owner}), AbstractRoutingLogic(address(0))
    );
  }
}
