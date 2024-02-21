// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "../../abstract/AbstractRoutingLogic.sol";
import {MonoswapV3Manager} from "./MonoswapV3Manager.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {PoolAddress} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@mgv-strats/src/strategies/vendor/uniswap/v3/core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/libraries/LiquidityAmounts.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

contract MonoswapV3RoutingLogic is AbstractRoutingLogic {
  MonoswapV3Manager public immutable manager;
  INonfungiblePositionManager public immutable positionManager;
  address public immutable factory;

  struct Position {
    uint96 nonce;
    address operator;
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint feeGrowthInside0LastX128;
    uint feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
  }

  constructor(MonoswapV3Manager _manager) {
    manager = _manager;
    positionManager = _manager.positionManager();
    factory = positionManager.factory();
  }

  function _positionFromID(uint positionId) internal view returns (Position memory position) {
    (bool success, bytes memory data) =
      address(positionManager).staticcall(abi.encodeWithSelector(positionManager.positions.selector, positionId));
    require(success, "MV3RoutingLogic/position-not-found");
    position = abi.decode(data, (Position));
  }

  function _getPosition(address fundOwner) internal view returns (uint positionId, Position memory position) {
    positionId = manager.positions(fundOwner);
    position = _positionFromID(positionId);
  }

  function _getPoolKey(address token0, address token1, uint24 fee)
    internal
    pure
    returns (PoolAddress.PoolKey memory poolKey)
  {
    poolKey = PoolAddress.getPoolKey(token0, token1, fee);
  }

  function _getPool(PoolAddress.PoolKey memory poolKey) internal view returns (IUniswapV3Pool pool) {
    return IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
  }

  function _owedOf(IERC20 _token, Position memory position) internal pure returns (uint owed) {
    address token = address(_token);
    if (token == position.token0) {
      owed = position.tokensOwed0;
    }
    if (token == position.token1) {
      owed = position.tokensOwed1;
    }
  }

  function _inManager(IERC20 token, address fundOwner) internal view returns (uint) {
    return manager.balances(fundOwner, token);
  }

  function _collect(uint positionId) internal returns (uint amount0, uint amount1) {
    INonfungiblePositionManager.CollectParams memory params;
    params.tokenId = positionId;
    params.recipient = address(this);
    params.amount0Max = type(uint128).max;
    params.amount1Max = type(uint128).max;
    (amount0, amount1) = positionManager.collect(params);
  }

  function _takeAllFromManager(IERC20 token0, IERC20 token1, address fundOwner) internal {
    // take all from manager
    uint balance0 = manager.balances(fundOwner, token0);
    if (balance0 > 0) {
      manager.routerTakeAmountTo(fundOwner, token0, balance0, address(this));
    }
    uint balance1 = manager.balances(fundOwner, token1);
    if (balance1 > 0) {
      manager.routerTakeAmountTo(fundOwner, token1, balance1, address(this));
    }
  }

  function _sendAllToManager(IERC20 token0, IERC20 token1, address fundOwner) internal {
    // send all to manager
    uint balance0 = token0.balanceOf(address(this));
    if (balance0 > 0) {
      require(TransferLib.approveToken(token0, address(manager), balance0), "MV3RoutingLogic/approve-failed");
      manager.addToBalance(fundOwner, token0, balance0);
    }
    uint balance1 = token1.balanceOf(address(this));
    if (balance1 > 0) {
      require(TransferLib.approveToken(token1, address(manager), balance1), "MV3RoutingLogic/approve-failed");
      manager.addToBalance(fundOwner, token1, balance1);
    }
  }

  function _reposition(uint positionId, IERC20 token0, IERC20 token1, address fundOwner) internal {
    // take all tokens possible everywhere
    _takeAllFromManager(token0, token1, fundOwner);
    _collect(positionId);
    // check balances of amount 0 and amount 1
    uint amount0Desired = token0.balanceOf(address(this));
    uint amount1Desired = token1.balanceOf(address(this));
    // give allowance to the position manager for these tokens
    TransferLib.approveToken(token0, address(positionManager), amount0Desired);
    TransferLib.approveToken(token1, address(positionManager), amount1Desired);
    // reposition
    INonfungiblePositionManager.IncreaseLiquidityParams memory params;
    params.tokenId = positionId;
    params.amount0Desired = amount0Desired;
    params.amount1Desired = amount1Desired;
    params.deadline = type(uint).max;
    try positionManager.increaseLiquidity(params) {} catch {}
  }

  function _amountsInPosition(Position memory position) internal view returns (uint amount0, uint amount1) {
    (uint160 sqrtPriceX96,,,,,,) = _getPool(_getPoolKey(position.token0, position.token1, position.fee)).slot0();
    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);
    (amount0, amount1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, position.liquidity);
  }

  // pull => take all => collect => send to msg.sender => reposition => send remaining to manager

  function pullLogic(IERC20 token, address fundOwner, uint amount, bool)
    external
    virtual
    override
    returns (uint pulled)
  {
    // get the position
    (uint positionId, Position memory position) = _getPosition(fundOwner);
    // preflight checks to save gas in case of failure

    // remove position if we don't have enough when collecting
    if (_owedOf(token, position) + _inManager(token, fundOwner) < amount) {
      // remove full position
      INonfungiblePositionManager.DecreaseLiquidityParams memory params;
      params.tokenId = positionId;
      params.liquidity = position.liquidity;
      params.deadline = type(uint).max;
      positionManager.decreaseLiquidity(params);
      // update the position in memory
      position = _positionFromID(positionId);
    }
    // collect
    _collect(positionId);
    // take all tokens from manager
    _takeAllFromManager(IERC20(position.token0), IERC20(position.token1), fundOwner);
    // send to msg.sender
    require(TransferLib.transferToken(token, msg.sender, amount), "MV3RoutingLogic/pull-failed");
    // try to reposition with the given amounts of token0 and token1
    _reposition(positionId, IERC20(position.token0), IERC20(position.token1), fundOwner);
    // send remaining amount of token0 and token1 to manager
    _sendAllToManager(IERC20(position.token0), IERC20(position.token1), fundOwner);
    // return amount
    return amount;
  }

  // push => take from msg.sender => take all => collect => reposition => send remaining to manager

  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual override returns (uint pushed) {
    // push directly to manager (avoid gas vost of trying to reposition)
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "MV3RoutingLogic/push-failed");
    // get the position choosen by the user
    (uint positionId, Position memory position) = _getPosition(fundOwner);
    // collect all to this
    _collect(positionId);
    // take all tokens from manager
    _takeAllFromManager(IERC20(position.token0), IERC20(position.token1), fundOwner);
    // reposition
    _reposition(positionId, IERC20(position.token0), IERC20(position.token1), fundOwner);
    // send remaining amount of token0 and token1 to manager
    _sendAllToManager(IERC20(position.token0), IERC20(position.token1), fundOwner);
    // return amount
    return amount;
  }

  function _balanceOf(IERC20 token, address fundOwner, Position memory position)
    internal
    view
    returns (uint managerBalance, uint owed, uint inPosition)
  {
    // amount in manager + amount owed + amount from liquidity
    // amount in manager
    managerBalance = manager.balances(fundOwner, token);
    // amount owed
    owed = _owedOf(token, position);
    // amount from liquidity
    (uint amount0, uint amount1) = _amountsInPosition(position);
    if (address(token) == position.token0) {
      inPosition = amount0;
    }
    if (address(token) == position.token1) {
      inPosition = amount1;
    }
  }

  function balanceLogic(IERC20 token, address fundOwner) external view virtual override returns (uint balance) {
    (, Position memory position) = _getPosition(fundOwner);
    (uint managerBalance, uint owed, uint inPosition) = _balanceOf(token, fundOwner, position);
    balance = managerBalance + owed + inPosition;
  }
}
