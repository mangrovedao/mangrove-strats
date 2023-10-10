// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {SimpleVaultRouter} from "../../abstract/SimpleVaultRouter.sol";
import {AbstractRouter} from "../../abstract/AbstractRouter.sol";
import {IERC20} from "mgv_lib/IERC20.sol";
import {IStargateRouter} from "mgv_strat_src/strategies/vendor/stargate/IStargateRouter.sol";
import {IFactory} from "mgv_strat_src/strategies/vendor/stargate/IFactory.sol";
import {IPool} from "mgv_strat_src/strategies/vendor/stargate/IPool.sol";

/// @title `StargateDispatchedRouter` is a router contract for Stargate Pools.
contract StargateDispatchedRouter is SimpleVaultRouter {
  /// @notice The StargateRouter contract
  IStargateRouter public immutable stargateRouter;

  /// @notice contract's constructor
  /// @param routerGasreq_ The gas requirement for the router
  /// @param _stargateRouter The StargateRouter contract
  constructor(uint routerGasreq_, IStargateRouter _stargateRouter) SimpleVaultRouter(routerGasreq_) {
    stargateRouter = _stargateRouter;
  }

  /// @inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint balance) {
    address vaultToken = __vault_token__(token);
    require(vaultToken != address(0), "SimpleVaultRouter/InvalidToken");
    IPool pool = IPool(vaultToken);
    return token.balanceOf(reserveId) + pool.amountLPtoLD(pool.balanceOf(reserveId));
  }

  /// @inheritdoc SimpleVaultRouter
  function __vault_token__(IERC20 token) internal view virtual override returns (address vaultToken) {
    IFactory factory = stargateRouter.factory();
    uint length = factory.allPoolsLength();
    // TODO: check if we want to add pool ids manually to save gas
    for (uint i = 0; i < length; i++) {
      IPool pool = IPool(factory.allPools(i));
      if (pool.token() == address(token)) {
        return address(pool);
      }
    }
  }

  /// @inheritdoc SimpleVaultRouter
  function __deposit__(IERC20 token, uint amount, address onBehalf) internal virtual override {
    address vaultToken = __vault_token__(token);
    require(vaultToken != address(0), "SimpleVaultRouter/InvalidToken");
    IPool pool = IPool(vaultToken);

    stargateRouter.addLiquidity(pool.poolId(), amount, onBehalf);
  }

  /// @notice Gets the amount of LP for a given amount of token in local decimals
  /// @param _amountLD The amount of token in local decimals
  /// @param pool The pool to get the amount of LP for
  /// @return amountLP The amount of LP for a given amount of token in local decimals
  function amountLDtoLP(uint _amountLD, IPool pool) internal view returns (uint) {
    uint _amountSD = _amountLD / pool.convertRate();
    uint totalLiquidity = pool.totalLiquidity();
    require(totalLiquidity > 0, "StargateDispatchedRouter/NoLiquidity");
    return _amountSD * pool.totalSupply() / totalLiquidity;
  }

  /// @inheritdoc SimpleVaultRouter
  function __withdraw__(IERC20 token, uint amount, address to) internal virtual override returns (uint) {
    address vaultToken = __vault_token__(token);
    require(vaultToken != address(0), "SimpleVaultRouter/InvalidToken");
    IPool pool = IPool(vaultToken);

    uint amountLP = amountLDtoLP(amount, pool);

    return stargateRouter.instantRedeemLocal(pool.poolId(), amountLP, to);
  }
}
