// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";

/// @title Monoswap V3 Manager
/// @author Mangrove DAO
/// @notice This contract is used to manage Monoswap V3 positions used by the mangrove strategy
/// * This contract holds the position ID for the managed positions
/// * It also holds the balances of the tokens that cannot be reinvested immediately into the strategy
contract MonoswapV3Manager {
  /// @notice The position manager contract
  INonfungiblePositionManager public immutable positionManager;

  /// @notice The router implementation contract
  AbstractRouter public immutable ROUTER_IMPLEMENTATION;

  /// @notice The router proxy factory contract
  RouterProxyFactory public immutable routerProxyFactory;

  /// @notice The managers mapping
  mapping(address owner => mapping(address manager => bool isManager)) public managers;

  /// @notice The positions mapping
  mapping(address owner => uint position) public positions;

  /// @notice The balances mapping
  mapping(address owner => mapping(IERC20 token => uint balance)) public balances;

  /// @notice Fires when a manager is added
  /// @param user the user address
  /// @param manager the manager address
  event ManagerAdded(address indexed user, address indexed manager);

  /// @notice Fires when a manager is removed
  /// @param user the user address
  /// @param manager the manager address
  event ManagerRemoved(address indexed user, address indexed manager);

  /// @notice Fires when a position is changed
  /// @param user the user address
  /// @param positionId the position ID
  event PositionChanged(address indexed user, uint indexed positionId);

  /// @notice Fires when a balance is changed
  /// @param user the user address
  /// @param token the token address
  /// @param balance the new balance for the token
  event BalanceChanged(address indexed user, IERC20 indexed token, uint balance);

  /// @notice Modifier to allow only the user or a manager to call a function
  /// @param _user the user address
  modifier onlyAllowed(address _user) {
    require(_user == msg.sender || managers[_user][msg.sender], "MV3Manager/not-allowed");
    _;
  }

  /// @notice Modifier to allow only the user router to call a function
  /// @param _user the user address
  modifier onlyUserRouter(address _user) {
    require(userRouter(_user) == msg.sender, "MV3Manager/not-allowed");
    _;
  }

  /// @notice Contract constructor
  /// @param _positionManager the position manager contract
  /// @param _routerProxyFactory the router proxy factory contract
  /// @param _routerImplementation the router implementation contract
  constructor(
    INonfungiblePositionManager _positionManager,
    RouterProxyFactory _routerProxyFactory,
    AbstractRouter _routerImplementation
  ) {
    positionManager = _positionManager;
    routerProxyFactory = _routerProxyFactory;
    ROUTER_IMPLEMENTATION = _routerImplementation;
  }

  /// @notice Returns the user router address
  /// @param _user the user address
  /// @return router the user router address
  function userRouter(address _user) public view returns (address) {
    return routerProxyFactory.computeProxyAddress(_user, ROUTER_IMPLEMENTATION);
  }

  /// @notice Adds a manager
  /// @param _user the user address
  /// @param _manager the manager address
  function addManager(address _user, address _manager) external onlyAllowed(_user) {
    managers[_user][_manager] = true;
    emit ManagerAdded(_user, _manager);
  }

  /// @notice Removes a manager
  /// @param _user the user address
  /// @param _manager the manager address
  function removeManager(address _user, address _manager) external onlyAllowed(_user) {
    managers[_user][_manager] = false;
    emit ManagerRemoved(_user, _manager);
  }

  /// @notice Changes the position ID
  /// @param _user the user address
  /// @param _positionId the position ID
  function changePosition(address _user, uint _positionId) external onlyAllowed(_user) {
    positions[_user] = _positionId;
    emit PositionChanged(_user, _positionId);
  }

  /// @notice Retracts the balance of a token
  /// @dev No safety checks are performed
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _amount the amount retracted from the balance
  /// @param _destination the destination address
  function _retractBalance(address _user, IERC20 _token, uint _amount, address _destination) internal {
    require(balances[_user][_token] >= _amount, "MV3Manager/insufficient-balance");
    require(TransferLib.transferToken(_token, _destination, _amount), "MV3Manager/transfer-failed");
    uint balance = balances[_user][_token] - _amount;
    balances[_user][_token] = balance;
    emit BalanceChanged(_user, _token, balance);
  }

  /// @notice Retracts the balance of a token
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  function retractBalance(address _user, IERC20 _token) external onlyAllowed(_user) {
    _retractBalance(_user, _token, balances[_user][_token], _user);
  }

  /// @notice Retracts the balance of a token
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _destination the destination address
  function retractBalanceTo(address _user, IERC20 _token, address _destination) external onlyAllowed(_user) {
    _retractBalance(_user, _token, balances[_user][_token], _destination);
  }

  /// @notice Retracts an amount of a token from the balance
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _amount the amount retracted from the balance
  function retractAmout(address _user, IERC20 _token, uint _amount) external onlyAllowed(_user) {
    _retractBalance(_user, _token, _amount, _user);
  }

  /// @notice Retracts an amount of a token from the balance
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _amount the amount retracted from the balance
  /// @param _destination the destination address
  function retractAmountTo(address _user, IERC20 _token, uint _amount, address _destination)
    external
    onlyAllowed(_user)
  {
    _retractBalance(_user, _token, _amount, _destination);
  }

  /// @notice Adds to the balance of a token
  /// @param _user the user address
  /// @param _token the token added to the balance
  /// @param _amount the amount added to the balance
  function addToBalance(address _user, IERC20 _token, uint _amount) external onlyUserRouter(_user) {
    require(TransferLib.transferTokenFrom(_token, msg.sender, address(this), _amount), "MV3Manager/transfer-failed");
    uint balance = balances[_user][_token] + _amount;
    balances[_user][_token] = balance;
    emit BalanceChanged(_user, _token, balance);
  }

  /// @notice Takes an amount from the balance of a token
  /// @param _user the user address
  /// @param _token the token taken from the balance
  /// @param _amount the amount taken from the balance
  function routerTakeAmount(address _user, IERC20 _token, uint _amount) external onlyUserRouter(_user) {
    _retractBalance(_user, _token, _amount, msg.sender);
  }
}
