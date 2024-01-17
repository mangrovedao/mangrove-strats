// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {IERC20} from "@mgv/src/core/MgvLib.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

import {IStargateRouter} from "@mgv-strats/src/strategies/vendor/stargate/IStargateRouter.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/stargate/IPool.sol";
import {IFactory} from "@mgv-strats/src/strategies/vendor/stargate/IFactory.sol";

/// @title StargateLender
/// @notice Logic to interact with Stargate pools. It may only deposit/redeem the asset of the pool.
contract StargateLender {
  /// @notice The StargateRouter pool contract
  IPool public immutable POOL;

  /// @notice The pool id to deposit/withdraw from
  uint16 public immutable POOL_ID;

  /// @notice The StargateRouter factory contract
  IFactory public immutable FACTORY;

  /// @notice The StargateRouter contract
  IStargateRouter public immutable STARGATE_ROUTER;

  /// @notice Constructor
  /// @param factory The StargateRouter factory contract
  /// @param poolId The pool id to deposit/withdraw from
  constructor(IFactory factory, uint poolId) {
    require(address(factory) != address(0), "StargateLogic/0xFactory");
    FACTORY = factory;
    POOL = IPool(address(factory.getPool(poolId)));
    require(uint16(poolId) == poolId, "StargateLogic/IdOverflow");
    POOL_ID = uint16(poolId);
    require(address(POOL) != address(0), "StargateLogic/0xPool");
    STARGATE_ROUTER = IStargateRouter(factory.router());
    require(address(STARGATE_ROUTER) != address(0), "StargateLogic/0xRouter");
  }

  /// @notice The underlying asset of the pool
  function underlying() public view returns (IERC20 token) {
    return IERC20(POOL.token());
  }

  function overlying() public view returns (IERC20 xToken) {
    return IERC20(address(POOL));
  }

  function _deposit(uint amount, address onBehalf) internal returns (uint) {
    STARGATE_ROUTER.addLiquidity(POOL_ID, amount, onBehalf);
    return amount;
  }

  function _withdraw(uint amount, address to) internal returns (uint) {
    uint amountLP = POOL.amountLDtoLP(amount);
    return STARGATE_ROUTER.instantRedeemLocal(POOL_ID, amountLP, to);
  }
}
