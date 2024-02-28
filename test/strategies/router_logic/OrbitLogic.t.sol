// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MgvLib, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

import {RouterProxyFactory, RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {SmartRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

import {OrbitDeployer, OErc20} from "@mgv-strats/src/toy_strategies/utils/OrbitDeployer.sol";

import {OrbitLogic, OrbitLogicStorage} from "@mgv-strats/src/strategies/routing_logic/orbit/OrbitLogic.sol";
import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";
import {OrbitFork} from "@mgv-strats/src/toy_strategies/utils/OrbitFork.sol";

contract OrbitLogic_Test is StratTest {
  address user;

  RouterProxyFactory public proxyFactory;
  SmartRouter public routerImplementation;
  SmartRouter public router;

  OrbitLogic orbitLogic;
  OrbitLogicStorage orbitLogicStorage;

  IERC20 USDB = IERC20(0x4200000000000000000000000000000000000022);

  uint constant MIN_VOLUME = 1;

  function setUp() public override {
    OrbitFork fork = new OrbitFork();
    fork.setUp();

    user = freshAddress("user");

    proxyFactory = new RouterProxyFactory();
    routerImplementation = new SmartRouter(address(this));
    (RouterProxy proxy,) = proxyFactory.instantiate(user, routerImplementation);
    router = SmartRouter(address(proxy));

    orbitLogic = new OrbitLogic(fork.spaceStation());
    orbitLogicStorage = orbitLogic.orbitStorage();
  }

  function getRoutingOrder(IERC20 token) internal view returns (RL.RoutingOrder memory order) {
    order.fundOwner = user;
    order.token = token;
  }

  function setLogic(IERC20 token) internal {
    RL.RoutingOrder memory order = getRoutingOrder(token);
    vm.prank(user);
    router.setLogic(order, orbitLogic);
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
    push(USDB, amount);
    assertApproxEqAbs(orbitLogic.balanceLogic(USDB, user), amount, 1);
  }

  function test_push_pull() public {
    uint pushAmount = 15.1231 ether;

    push(USDB, pushAmount);
    assertApproxEqAbs(orbitLogic.balanceLogic(USDB, user), pushAmount, 1);

    // uint pullAmount = 10.1 ether;

    // uint pulled = pull(USDB, pullAmount);
    // assertApproxEqAbs(pulled, pullAmount, 1);
  }
}
