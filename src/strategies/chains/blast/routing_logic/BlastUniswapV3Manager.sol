// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
  UniswapV3Manager,
  INonfungiblePositionManager,
  RouterProxyFactory,
  AbstractRouter
} from "@mgv-strats/src/strategies/routing_logic/restaking/uni-v3/UniswapV3Manager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Rebasing, YieldMode} from "@mgv-strats/src/strategies/vendor/blast/IERC20Rebasing.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/// @title BlastUniswapV3Manager
/// @author Mangrove
/// @notice A UniswapV3Manager that can handle rebasing tokens from Blast
contract BlastUniswapV3Manager is UniswapV3Manager, Ownable, IBlastPoints {
  /// @notice Constructor
  /// @param _initTokens The tokens to initialize
  /// @param admin the admin address
  /// @param positionManager the position manager
  /// @param factory the router proxy factory
  /// @param implementation the router implementation
  constructor(
    IERC20Rebasing[] memory _initTokens,
    address admin,
    INonfungiblePositionManager positionManager,
    RouterProxyFactory factory,
    AbstractRouter implementation
  ) UniswapV3Manager(positionManager, factory, implementation) Ownable(admin) {
    for (uint i = 0; i < _initTokens.length; i++) {
      _initRebasingToken(_initTokens[i]);
    }
  }

  /// @notice Initializes a rebasing token with the correct yield mode
  /// @param token The token to configure
  function _initRebasingToken(IERC20Rebasing token) internal {
    token.configure(YieldMode.CLAIMABLE);
  }

  /// @notice Initializes a rebasing token with the correct yield mode
  /// @param token The token to configure
  function initRebasingToken(IERC20Rebasing token) external onlyOwner {
    _initRebasingToken(token);
  }

  /// @notice Claims yield from a rebasing token
  /// @param token The token to claim from
  function claim(IERC20Rebasing token, address recipient, uint amount) external onlyOwner {
    token.claim(recipient, amount);
  }

  /// @inheritdoc IBlastPoints
  function blastPointsAdmin() external view override returns (address) {
    return owner();
  }
}
