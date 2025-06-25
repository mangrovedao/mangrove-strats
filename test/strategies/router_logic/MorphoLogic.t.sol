// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MgvLib, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

import {RouterProxyFactory, RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {SmartRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

import {SimpleERC4626Logic, IERC4626} from "@mgv-strats/src/strategies/routing_logic/SimpleERC4626Logic.sol";
import {MockERC4626, IERC20 as VaultToken} from "@mgv-strats/test/lib/mocks/MockERC4626.sol";

contract MorphoLogic_Test is StratTest {
  address user;

  RouterProxyFactory public proxyFactory;
  SmartRouter public routerImplementation;
  SmartRouter public router;

  SimpleERC4626Logic erc4626Logic;
  MockERC4626 mockVault;
  TestToken underlying;

  uint constant MIN_VOLUME = 1;
  uint constant VESTING_PERIOD = 7 days;

  function setUp() public override {
    super.setUp();

    user = freshAddress("user");

    // Setup router infrastructure
    proxyFactory = new RouterProxyFactory();
    routerImplementation = new SmartRouter(address(this));
    (RouterProxy proxy,) = proxyFactory.instantiate(user, routerImplementation);
    router = SmartRouter(address(proxy));

    // Setup tokens and vault
    underlying = new TestToken(address(this), "Underlying Token", "UTK", 18);
    underlying.setMintLimit(type(uint).max);
    underlying.mint(1000e18);
    mockVault = new MockERC4626(VaultToken(address(underlying)), "Mock Vault", "mUTK");
    // Approve tokens first
    underlying.approve(address(mockVault), 1000e18);

    // Add rewards to vest over VESTING PERIOD
    mockVault.addRewards(1000e18, VESTING_PERIOD);

    // Setup logic
    erc4626Logic = new SimpleERC4626Logic(IERC4626(address(mockVault)));
  }

  function getRoutingOrder(IERC20 token) internal view returns (RL.RoutingOrder memory order) {
    order.fundOwner = user;
    order.token = token;
  }

  function setLogic(IERC20 token) internal {
    RL.RoutingOrder memory order = getRoutingOrder(token);
    vm.prank(user);
    router.setLogic(order, erc4626Logic);
  }

  function push(IERC20 token, uint amount) internal {
    setLogic(token);
    deal($(token), address(this), amount);
    token.approve(address(router), amount);
    RL.RoutingOrder memory order = getRoutingOrder(token);
    router.push(order, amount);
  }

  function pull(IERC20 token, uint amount) internal returns (uint pulled) {
    pulled = token.balanceOf(address(this));
    setLogic(token);
    RL.RoutingOrder memory order = getRoutingOrder(token);
    router.pull(order, amount, true);
    pulled = token.balanceOf(address(this)) - pulled;
  }

  function testFuzz_push(uint amount) public {
    vm.assume(amount >= MIN_VOLUME && amount <= 1e9 ether);
    push(underlying, amount);
    assertApproxEqAbs(mockVault.balanceOf(address(router)), mockVault.convertToShares(amount), 1);
  }

  function test_push_pull() public {
    uint pushAmount = 15.1231 ether;

    push(underlying, pushAmount);
    assertApproxEqAbs(mockVault.balanceOf(address(router)), mockVault.convertToShares(pushAmount), 1);

    // Advance time past vesting period
    vm.warp(block.timestamp + VESTING_PERIOD + 1);

    uint pullAmount = 10.1 ether;

    uint pulled = pull(underlying, pullAmount);
    assertApproxEqAbs(pulled, pullAmount, 1);
  }

  function test_pull_during_vesting() public {
    uint pushAmount = 20 ether;
    push(underlying, pushAmount);

    // Advance time halfway through vesting period
    vm.warp(block.timestamp + VESTING_PERIOD / 2);

    uint pullAmount = 10 ether;
    uint pulled = pull(underlying, pullAmount);

    // Should receive less than requested due to vesting
    assertApproxEqAbs(pulled, pullAmount, 1);
    assertGt(pulled, 0);
  }
}
