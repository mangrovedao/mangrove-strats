// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "../../abstract/AbstractRoutingLogic.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {SimpleLogicWithHooks} from "../../SimpleLogicWithHooks.sol";
import {INonfungiblePositionManager} from "@mgv-strats/src/strategies/vendor/monoswap/INonFungiblePositionManager.sol";
import {MonoswapMgvManager} from "./MonoswapMgvManager.sol";

contract MonoswapV3Restaker is SimpleLogicWithHooks {
  INonfungiblePositionManager public immutable positionManager;

  MonoswapMgvManager public immutable mgvManager;

  constructor(INonfungiblePositionManager _positionManager, MonoswapMgvManager _mgvManager) {
    positionManager = _positionManager;
    mgvManager = _mgvManager;
  }

  function __onPullAfter__(IERC20, address fundOwner, uint, bool) internal override {
    uint[] memory positions = mgvManager.positions(fundOwner);
  }

  function _restakePosition(uint positionId, address owner) internal {
    (
      uint96 nonce,
      address operator,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint feeGrowthInside0LastX128,
      uint feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    ) = positionManager.positions(positionId);

    INonfungiblePositionManager.CollectParams memory params;
    params.tokenId = positionId;
    params.recipient = address(this);
  }
}
