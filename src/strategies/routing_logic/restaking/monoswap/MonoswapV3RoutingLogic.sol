// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "../../abstract/AbstractRoutingLogic.sol";
import {MonoswapV3Manager} from "./MonoswapV3Manager.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";

contract MonoswapV3RoutingLogic is AbstractRoutingLogic {
  MonoswapV3Manager public immutable manager;
  INonfungiblePositionManager public immutable positionManager;

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
  }

  function _getPosition(address fundOwner) internal view returns (uint positionId, Position memory position) {
    positionId = manager.positions(fundOwner);
    (
      position.nonce,
      position.operator,
      position.token0,
      position.token1,
      position.fee,
      position.tickLower,
      position.tickUpper,
      position.liquidity,
      position.feeGrowthInside0LastX128,
      position.feeGrowthInside1LastX128,
      position.tokensOwed0,
      position.tokensOwed1
    ) = positionManager.positions(positionId);
  }

  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict)
    external
    virtual
    override
    returns (uint pulled)
  {
    (uint positionId, Position memory position) = _getPosition(fundOwner);
  }

  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual override returns (uint pushed) {}

  function balanceLogic(IERC20 token, address fundOwner) external view virtual override returns (uint balance) {}
}
