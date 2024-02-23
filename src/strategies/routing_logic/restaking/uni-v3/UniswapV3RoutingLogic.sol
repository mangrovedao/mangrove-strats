// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "../../abstract/AbstractRoutingLogic.sol";
import {UniswapV3Manager} from "./UniswapV3Manager.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {PoolAddress} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/libraries/PoolAddress.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@mgv-strats/src/strategies/vendor/uniswap/v3/core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/libraries/LiquidityAmounts.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title UniswapV3RoutingLogic
/// @author Mangrove DAO
/// @notice This contract is used to manage the routing logic for Uniswap V3
contract UniswapV3RoutingLogic is AbstractRoutingLogic {
  /// @notice The Uniswap V3 manager contract
  UniswapV3Manager public immutable manager;

  /// @notice The Uniswap V3 position manager contract
  INonfungiblePositionManager public immutable positionManager;

  /// @notice The Uniswap V3 factory address
  address public immutable factory;

  /// @notice The Uniswap V3 position struct
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

  /// @notice Construct the Uniswap V3 routing logic
  /// @param _manager the Uniswap V3 manager contract
  constructor(UniswapV3Manager _manager) {
    manager = _manager;
    positionManager = _manager.positionManager();
    factory = positionManager.factory();
  }

  /// @notice Get the position from the position ID
  /// @param positionId the position ID
  /// @return position the position struct
  function _positionFromID(uint positionId) internal view returns (Position memory position) {
    (bool success, bytes memory data) =
      address(positionManager).staticcall(abi.encodeWithSelector(positionManager.positions.selector, positionId));
    require(success, "MV3RoutingLogic/position-not-found");
    position = abi.decode(data, (Position));
  }

  /// @notice Get the position from the fund owner
  /// @param fundOwner the fund owner address
  /// @return positionId the position ID
  /// @return position the position struct
  function _getPosition(address fundOwner) internal view returns (uint positionId, Position memory position) {
    positionId = manager.positions(fundOwner);
    position = _positionFromID(positionId);
  }

  function _anyOfToken(IERC20 token, Position memory position) internal pure {
    require(token == IERC20(position.token0) || token == IERC20(position.token1), "MV3RoutingLogic/invalid-token");
  }

  /// @notice Gets the current price from a pool
  /// @param token0 The first token
  /// @param token1 The second token
  /// @param fee The fee
  function getCurrentSqrtRatioX96(address token0, address token1, uint24 fee)
    internal
    view
    returns (uint160 sqrtPriceX96)
  {
    PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(token0, token1, fee);
    IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
    (sqrtPriceX96,,,,,,) = pool.slot0();
  }

  /// @notice Get the amount owed of a token given a position
  /// @param _token the token
  /// @param position the position
  /// @return owed the amount owed
  function _owedOf(IERC20 _token, Position memory position) internal pure returns (uint owed) {
    address token = address(_token);
    if (token == position.token0) {
      owed = position.tokensOwed0;
    }
    if (token == position.token1) {
      owed = position.tokensOwed1;
    }
  }

  /// @notice Get the amount in the manager
  /// @param token the token
  /// @param fundOwner the fund owner
  /// @return inManager the amount in the manager
  function _inManager(IERC20 token, address fundOwner) internal view returns (uint) {
    return manager.balances(fundOwner, token);
  }

  /// @notice Collect the fees from a position (or unused tokens)
  /// @param positionId the position ID
  /// @return amount0 the amount of token0
  /// @return amount1 the amount of token1
  function _collect(uint positionId) internal returns (uint amount0, uint amount1) {
    INonfungiblePositionManager.CollectParams memory params;
    params.tokenId = positionId;
    params.recipient = address(this);
    params.amount0Max = type(uint128).max;
    params.amount1Max = type(uint128).max;
    (amount0, amount1) = positionManager.collect(params);
  }

  /// @notice Get the tokens array
  /// @param token the token in logic
  /// @param token0 the first token
  /// @param token1 the second token
  function _getTokensArray(IERC20 token, IERC20 token0, IERC20 token1) internal pure returns (IERC20[] memory tokens) {
    if (token == token0 || token == token1) {
      tokens = new IERC20[](2);
    } else {
      tokens = new IERC20[](3);
      tokens[2] = token;
    }
    tokens[0] = token0;
    tokens[1] = token1;
  }

  /// @notice Take all tokens from the manager
  /// @param tokens the tokens
  /// @param fundOwner the fund owner
  function _takeAllFromManager(IERC20[] memory tokens, address fundOwner) internal {
    uint[] memory amounts;
    (tokens, amounts) = manager.getFullBalancesParams(fundOwner, tokens);
    manager.routerTakeAmounts(fundOwner, tokens, amounts, address(this));
  }

  /// @notice Send all tokens to the manager
  /// @param tokens the tokens
  /// @param fundOwner the fund owner
  function _sendAllToManager(IERC20[] memory tokens, address fundOwner) internal {
    uint[] memory amounts = new uint[](tokens.length);
    for (uint i = 0; i < tokens.length; i++) {
      amounts[i] = tokens[i].balanceOf(address(this));
      if (amounts[i] > 0) {
        require(TransferLib.approveToken(tokens[i], address(manager), amounts[i]), "MV3RoutingLogic/approve-failed");
      }
    }
    manager.addToBalances(fundOwner, tokens, amounts);
  }

  /// @notice Approve the position manager for a given amount of tokens
  /// @param token the token to approve
  /// @param amount the amount to approve
  function _approvePositionManager(IERC20 token, uint amount) internal {
    require(TransferLib.approveToken(token, address(positionManager), amount), "MV3RoutingLogic/approve-failed");
  }

  /// @notice Reposition the position
  /// @param positionId the position ID
  /// @param token0 the first token
  /// @param token1 the second token
  function _reposition(uint positionId, IERC20 token0, IERC20 token1) internal {
    // check balances of amount 0 and amount 1
    uint amount0Desired = token0.balanceOf(address(this));
    uint amount1Desired = token1.balanceOf(address(this));
    // give allowance to the position manager for these tokens
    _approvePositionManager(token0, amount0Desired);
    _approvePositionManager(token1, amount1Desired);
    // reposition
    INonfungiblePositionManager.IncreaseLiquidityParams memory params;
    params.tokenId = positionId;
    params.amount0Desired = amount0Desired;
    params.amount1Desired = amount1Desired;
    params.deadline = type(uint).max;
    try positionManager.increaseLiquidity(params) {} catch {}
    // resetting allowances (ensure no allowance is left behind and gas refund for storage reset)
    _approvePositionManager(token0, 0);
    _approvePositionManager(token1, 0);
  }

  /// @notice Get the amounts in a position
  /// @param position the position
  /// @return amount0 the amount of token0
  /// @return amount1 the amount of token1
  function _amountsInPosition(Position memory position) internal view returns (uint amount0, uint amount1) {
    uint160 sqrtPriceX96 = getCurrentSqrtRatioX96(position.token0, position.token1, position.fee);
    uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
    uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);
    (amount0, amount1) =
      LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, position.liquidity);
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @dev the pull logics first checks if it has enough to collect and in manager to send to mangrove and avoid uneceesary decrease in liquidity
  /// * if not, we first decrease the full liquidity
  /// * In any case, we then collect from the position, remove all  tokens from the manager
  /// * Then we send the necessary amount to the maker contract
  /// * finally we reposition and send the remaining amount to the manager
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool)
    external
    virtual
    override
    returns (uint pulled)
  {
    // get the position
    (uint positionId, Position memory position) = _getPosition(fundOwner);
    // preflight checks to save gas in case of failure
    _anyOfToken(token, position);
    // remove position if we don't have enough when collecting
    if (_owedOf(token, position) + _inManager(token, fundOwner) < amount) {
      // remove full position
      INonfungiblePositionManager.DecreaseLiquidityParams memory params;
      params.tokenId = positionId;
      params.liquidity = position.liquidity;
      params.deadline = type(uint).max;
      positionManager.decreaseLiquidity(params);
      // update the position in memory
      // position = _positionFromID(positionId); // update not needed given the rest of the function only uses the tokens
    }
    // collect
    _collect(positionId);
    // create token array
    IERC20[] memory tokens = _getTokensArray(token, IERC20(position.token0), IERC20(position.token1));
    // take all tokens from manager
    _takeAllFromManager(tokens, fundOwner);
    // send to msg.sender
    require(TransferLib.transferToken(token, msg.sender, amount), "MV3RoutingLogic/pull-failed");
    // try to reposition with the given amounts of token0 and token1
    _reposition(positionId, IERC20(position.token0), IERC20(position.token1));
    // send remaining amount of token0 and token1 to manager
    _sendAllToManager(tokens, fundOwner);
    // return amount
    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  /// @dev the push logics first collect all fees from the position, then take all tokens from the manager
  /// * It then repositions the position and sends the remaining amount to the manager
  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual override returns (uint pushed) {
    // get the position choosen by the user
    (uint positionId, Position memory position) = _getPosition(fundOwner);
    // preflight checks to save gas in case of failure
    _anyOfToken(token, position);
    // push directly to manager (avoid gas vost of trying to reposition)
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "MV3RoutingLogic/push-failed");
    // collect all to this
    _collect(positionId);
    // Get tokens array
    IERC20[] memory tokens = _getTokensArray(token, IERC20(position.token0), IERC20(position.token1));
    // take all tokens from manager
    _takeAllFromManager(tokens, fundOwner);
    // reposition
    _reposition(positionId, IERC20(position.token0), IERC20(position.token1));
    // send remaining amount of token0 and token1 to manager
    _sendAllToManager(tokens, fundOwner);
    // return amount
    return amount;
  }

  /// @notice Get the balance of a token
  /// @param token The token
  /// @param fundOwner The fund owner
  /// @param position The position
  /// @return managerBalance the amount in the manager
  /// @return owed the amount owed by the position
  /// @return inPosition the amount in the position
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

  /// @inheritdoc AbstractRoutingLogic
  function balanceLogic(IERC20 token, address fundOwner) external view virtual override returns (uint balance) {
    (, Position memory position) = _getPosition(fundOwner);
    (uint managerBalance, uint owed, uint inPosition) = _balanceOf(token, fundOwner, position);
    balance = managerBalance + owed + inPosition;
  }
}
