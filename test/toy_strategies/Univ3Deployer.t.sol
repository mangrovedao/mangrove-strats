// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Univ3Deployer} from "@mgv-strats/src/toy_strategies/utils/Univ3Deployer.sol";
import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv-strats/test/lib/StratTest.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {PoolAddress} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "@mgv-strats/src/strategies/vendor/uniswap/v3/core/libraries/TickMath.sol";

contract Univ3Deployer_test is StratTest, Univ3Deployer {
  PinnedPolygonFork fork;

  event PoolCreated(
    address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool
  );

  function _getPoolKey(address token0, address token1, uint24 fee)
    internal
    pure
    returns (PoolAddress.PoolKey memory poolKey)
  {
    poolKey = PoolAddress.getPoolKey(token0, token1, fee);
  }

  function _getPool(PoolAddress.PoolKey memory poolKey) internal view returns (IUniswapV3Pool pool) {
    return IUniswapV3Pool(PoolAddress.computeAddress(address(factory), poolKey));
  }

  function setUp() public override {
    deployUniv3();

    fork = new PinnedPolygonFork(39880000);
    fork.setUp();

    base = TestToken(fork.get("WETH.e"));
    quote = TestToken(fork.get("DAI.e"));
  }

  function test_position_manager() public {
    assertEq(positionManager.name(), "Uniswap V3 Positions NFT-V1");
    assertEq(positionManager.symbol(), "UNI-V3-POS");
    assertEq(positionManager.factory(), address(factory));
    assertEq(positionManager.totalSupply(), 0);
  }

  function test_factory() public {
    assertEq(factory.owner(), address(this));
    assertEq(factory.feeAmountTickSpacing(500), 10);
    assertEq(factory.feeAmountTickSpacing(3000), 60);
    assertEq(factory.feeAmountTickSpacing(10000), 200);
  }

  function test_create_pool() public {
    IUniswapV3Pool exepextedPool = _getPool(PoolAddress.getPoolKey(address(base), address(quote), 500));
    vm.expectEmit();
    emit PoolCreated(address(base), address(quote), 500, 10, address(exepextedPool));
    address pool = factory.createPool(address(base), address(quote), 500);
    assertEq(pool, factory.getPool(address(base), address(quote), 500));
    assertEq(pool, address(exepextedPool));

    exepextedPool.initialize(TickMath.getSqrtRatioAtTick(0));

    assertEq(exepextedPool.token0(), address(base));
    assertEq(exepextedPool.token1(), address(quote));
    assertEq(exepextedPool.fee(), 500);
    assertEq(exepextedPool.tickSpacing(), 10);
    (,,,,,, bool unlocked) = exepextedPool.slot0();
    assertTrue(unlocked);
  }

  function test_addLiquidity() public {
    address pool = factory.createPool(address(base), address(quote), 500);
    IUniswapV3Pool(pool).initialize(TickMath.getSqrtRatioAtTick(0));

    INonfungiblePositionManager.MintParams memory params;
    params.token0 = address(base);
    params.token1 = address(quote);
    params.fee = 500;
    params.tickLower = -500;
    params.tickUpper = 500;
    params.deadline = block.timestamp + 1000;
    params.amount0Desired = 1000;
    params.amount1Desired = 1000;
    params.recipient = address(this);

    // base.mint(amount0Desired);
    // quote.mint(amount1Desired);
    deal($(base), address(this), params.amount0Desired);
    deal($(quote), address(this), params.amount1Desired);

    base.approve(address(positionManager), params.amount0Desired);
    quote.approve(address(positionManager), params.amount1Desired);

    positionManager.mint(params);

    assertEq(positionManager.balanceOf(address(this)), 1);
  }
}
