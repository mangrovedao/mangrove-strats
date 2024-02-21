// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {Univ3Deployer} from "@mgv-strats/src/toy_strategies/utils/Univ3Deployer.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "@mgv-strats/src/strategies/vendor/uniswap/v3/core/libraries/TickMath.sol";
import {MonoswapV3Manager} from "@mgv-strats/src/strategies/routing_logic/restaking/monoswap/MonoswapV3Manager.sol";
import {MonoswapV3RoutingLogic} from
  "@mgv-strats/src/strategies/routing_logic/restaking/monoswap/MonoswapV3RoutingLogic.sol";

import {RouterProxyFactory, RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {SmartRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

contract UniV3_Test is StratTest, Univ3Deployer {
  TestToken public token0;
  TestToken public token1;

  RouterProxyFactory public proxyFactory;
  SmartRouter public routerImplementation;
  SmartRouter public router;

  MonoswapV3Manager public manager;
  MonoswapV3RoutingLogic public routingLogic;

  IUniswapV3Pool public pool;

  uint positionId;

  function mintNewPosition() internal returns (uint _positionId) {
    INonfungiblePositionManager.MintParams memory params;
    params.token0 = address(token0);
    params.token1 = address(token1);
    params.fee = 500;
    params.tickLower = -500;
    params.tickUpper = 500;
    params.deadline = block.timestamp + 1000;
    params.amount0Desired = 1000;
    params.amount1Desired = 1000;
    params.recipient = address(this);

    deal($(token0), address(this), params.amount0Desired);
    deal($(token1), address(this), params.amount1Desired);

    token0.approve(address(positionManager), params.amount0Desired);
    token1.approve(address(positionManager), params.amount1Desired);

    (_positionId,,,) = positionManager.mint(params);
  }

  function getRoutingOrder(IERC20 token) internal view returns (RL.RoutingOrder memory order) {
    order.fundOwner = address(this);
    order.token = token;
  }

  function setLogic(IERC20 token) internal {
    RL.RoutingOrder memory order = getRoutingOrder(token);
    router.setLogic(order, routingLogic);
  }

  function setUp() public override {
    deployUniv3();

    token0 = new TestToken(address(this), "token0", "T0", 18);
    token1 = new TestToken(address(this), "token1", "T1", 18);

    pool = IUniswapV3Pool(factory.createPool(address(token0), address(token1), 500));
    pool.initialize(TickMath.getSqrtRatioAtTick(0));

    assertEq(pool.token0(), address(token0));
    assertEq(pool.token1(), address(token1));
    assertEq(pool.fee(), 500);
    assertEq(pool.tickSpacing(), 10);
    (,,,,,, bool unlocked) = pool.slot0();
    assertTrue(unlocked);

    proxyFactory = new RouterProxyFactory();
    // automatically binds to this
    routerImplementation = new SmartRouter(address(this));
    (RouterProxy proxy,) = proxyFactory.instantiate(address(this), routerImplementation);
    router = SmartRouter(address(proxy));

    manager = new MonoswapV3Manager(positionManager, proxyFactory, routerImplementation);
    routingLogic = new MonoswapV3RoutingLogic(manager);

    positionId = mintNewPosition();

    positionManager.approve(address(router), positionId);
    manager.changePosition(address(this), positionId);
    setLogic(token0);
    setLogic(token1);
  }

  function test_push() public {
    uint managerBalanceToken0 = manager.balances(address(this), token0);
    uint managerBalanceToken1 = manager.balances(address(this), token1);

    (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0, 0);
    assertEq(managerBalanceToken1, 0);

    uint amount = 1000;
    deal($(token0), address(this), amount);
    token0.approve(address(router), amount);
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    router.push(order, amount);

    uint managerBalanceToken0Step2 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step2 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep2,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step2, amount);
    assertEq(managerBalanceToken1Step2, 0);
    assertEq(liquidityStep2, liquidity);

    deal($(token1), address(this), amount);
    token1.approve(address(router), amount);
    order = getRoutingOrder(token1);
    router.push(order, amount);

    uint managerBalanceToken0Step3 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step3 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep3,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step3, 0);
    assertEq(managerBalanceToken1Step3, 0);
    assertEq(liquidityStep3, liquidity * 2);
  }

  function test_pull() public {
    uint managerBalanceToken0 = manager.balances(address(this), token0);
    uint managerBalanceToken1 = manager.balances(address(this), token1);

    (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0, 0);
    assertEq(managerBalanceToken1, 0);

    uint amount = 500;
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    router.pull(order, amount, true);

    uint managerBalanceToken0Step2 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step2 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep2,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken1Step2, amount);
    assertEq(managerBalanceToken0Step2, 0);
    assertApproxEqAbs(liquidityStep2, liquidity / 2, 100);

    order = getRoutingOrder(token1);
    router.pull(order, amount, true);

    uint managerBalanceToken0Step3 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step3 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep3,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step3, 0);
    assertEq(managerBalanceToken1Step3, 0);
    assertApproxEqAbs(liquidityStep3, liquidity / 2, 100);
  }

  function test_pull_too_much() public {
    uint amount = 10000;
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    vm.expectRevert();
    router.pull(order, amount, true);
  }

  function test_push_and_pull() public {
    (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

    uint amount = 1000;
    deal($(token0), address(this), amount);
    token0.approve(address(router), amount);
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    router.push(order, amount);

    uint managerBalanceToken0Step2 = manager.balances(address(this), token0);
    (,,,,,,, uint128 liquidityStep2,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step2, amount);
    assertEq(liquidityStep2, liquidity);

    router.pull(order, amount, true);

    uint managerBalanceToken0Step3 = manager.balances(address(this), token0);
    (,,,,,,, uint128 liquidityStep3,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step3, 0);
    assertEq(liquidityStep3, liquidity);
  }

  function test_push_imbalanced_ratios() public {
    uint managerBalanceToken0 = manager.balances(address(this), token0);
    uint managerBalanceToken1 = manager.balances(address(this), token1);

    (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0, 0);
    assertEq(managerBalanceToken1, 0);

    uint amount0 = 1000;
    deal($(token0), address(this), amount0);
    token0.approve(address(router), amount0);
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    router.push(order, amount0);

    uint managerBalanceToken0Step2 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step2 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep2,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step2, amount0);
    assertEq(managerBalanceToken1Step2, 0);
    assertEq(liquidityStep2, liquidity);

    uint amount1 = 500;

    deal($(token1), address(this), amount1);
    token1.approve(address(router), amount1);
    order = getRoutingOrder(token1);
    router.push(order, amount1);

    uint managerBalanceToken0Step3 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step3 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep3,,,,) = positionManager.positions(positionId);

    assertGt(managerBalanceToken0Step3, 0);
    assertEq(managerBalanceToken1Step3, 0);
    assertGt(liquidityStep3, liquidity);
  }

  function test_pull_imbalanced_ratios() public {
    uint managerBalanceToken0 = manager.balances(address(this), token0);
    uint managerBalanceToken1 = manager.balances(address(this), token1);

    (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0, 0);
    assertEq(managerBalanceToken1, 0);

    uint amount0 = 200;
    RL.RoutingOrder memory order = getRoutingOrder(token0);
    router.pull(order, amount0, true);

    uint managerBalanceToken0Step2 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step2 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep2,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step2, 0);
    assertEq(managerBalanceToken1Step2, amount0);
    assertLt(liquidityStep2, liquidity);

    uint amount1 = 500;
    order = getRoutingOrder(token1);
    router.pull(order, amount1, true);

    uint managerBalanceToken0Step3 = manager.balances(address(this), token0);
    uint managerBalanceToken1Step3 = manager.balances(address(this), token1);
    (,,,,,,, uint128 liquidityStep3,,,,) = positionManager.positions(positionId);

    assertEq(managerBalanceToken0Step3, amount1 - amount0);
    assertEq(managerBalanceToken1Step3, 0);
    assertLt(liquidityStep3, liquidityStep2);
  }
}
