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
    for (uint i = 0; i < positions.length; i++) {
      _restakePosition(positions[i], fundOwner);
    }
  }

  function _restakePosition(uint positionId, address owner) internal {
    (,, address token0, address token1,,,,,,, uint128 tokensOwed0, uint128 tokensOwed1) =
      positionManager.positions(positionId);

    // if one of the token fee balance is 0, we won't collect as it will end up not increasing liquidity
    if (tokensOwed0 == 0 && tokensOwed1 == 0) {
      return;
    }

    // collect the fees to this contract
    INonfungiblePositionManager.CollectParams memory params;
    params.tokenId = positionId;
    params.recipient = address(this);

    (uint amount0, uint amount1) = positionManager.collect(params);

    // increase the liquidity with the fee collected
    INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams;
    increaseParams.tokenId = positionId;
    increaseParams.amount0Desired = amount0;
    increaseParams.amount1Desired = amount1;

    require(TransferLib.approveToken(IERC20(token0), address(positionManager), amount0), "MSRV3/approve-failed");
    require(TransferLib.approveToken(IERC20(token1), address(positionManager), amount1), "MSRV3/approve-failed");

    positionManager.increaseLiquidity(increaseParams);

    // reset approvals
    require(TransferLib.approveToken(IERC20(token0), address(positionManager), 0), "MSRV3/reset-failed");
    require(TransferLib.approveToken(IERC20(token1), address(positionManager), 0), "MSRV3/reset-failed");

    // transfer ramining tokens to owner
    amount0 = IERC20(token0).balanceOf(address(this));
    amount1 = IERC20(token1).balanceOf(address(this));

    if (amount0 > 0) {
      require(TransferLib.transferToken(IERC20(token0), owner, amount0), "MSRV3/transfer-failed");
    }
    if (amount1 > 0) {
      require(TransferLib.transferToken(IERC20(token1), owner, amount1), "MSRV3/transfer-failed");
    }
  }
}
