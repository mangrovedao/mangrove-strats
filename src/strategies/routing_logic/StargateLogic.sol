// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {DispatcherRouter} from "@mgv-strats/src/strategies/routers/DispatcherRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {VaultLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/VaultLogic.sol";
import {IStargateRouter} from "@mgv-strats/src/strategies/vendor/stargate/IStargateRouter.sol";
import {IFactory} from "@mgv-strats/src/strategies/vendor/stargate/IFactory.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/stargate/IPool.sol";

/// @title StargateLogic
contract StargateLogic is VaultLogic {
  /// @notice The StargateRouter contract
  IStargateRouter public immutable STARGATE_ROUTER;

  /// @notice Constructor
  /// @param stargateRouter The StargateRouter contract
  /// @param pullGasReq_ gas requirements for `pull` logic execution regardless of the token
  /// @param pushGasReq_ gas requirements for `push` logic execution regardless of the token
  constructor(IStargateRouter stargateRouter, uint pullGasReq_, uint pushGasReq_) VaultLogic(pullGasReq_, pushGasReq_) {
    STARGATE_ROUTER = stargateRouter;
  }

  /// @inheritdoc VaultLogic
  function __vault_token__(IERC20 token) internal view virtual override returns (address vaultToken) {
    IFactory factory = STARGATE_ROUTER.factory();
    uint length = factory.allPoolsLength();
    // TODO: check if we want to add pool ids manually to save gas
    for (uint i = 0; i < length; i++) {
      IPool pool = IPool(factory.allPools(i));
      if (pool.token() == address(token)) {
        return address(pool);
      }
    }
  }

  /// @inheritdoc VaultLogic
  function __deposit__(IERC20 token, uint amount, address onBehalf) internal virtual override returns (uint) {
    address vaultToken = __vault_token__(token);
    require(vaultToken != address(0), "StargateLogic/UnsupportedToken");
    IPool pool = IPool(vaultToken);
    STARGATE_ROUTER.addLiquidity(pool.poolId(), amount, onBehalf);
    return amount;
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

  /// @inheritdoc VaultLogic
  function __withdraw__(IERC20 token, uint amount, address to) internal virtual override returns (uint) {
    address vaultToken = __vault_token__(token);
    require(vaultToken != address(0), "StargateLogic/UnsupportedToken");
    IPool pool = IPool(vaultToken);

    uint amountLP = amountLDtoLP(amount, pool);

    return STARGATE_ROUTER.instantRedeemLocal(pool.poolId(), amountLP, to);
  }
}
