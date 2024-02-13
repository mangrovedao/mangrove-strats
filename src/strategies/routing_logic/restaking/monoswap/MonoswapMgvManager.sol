// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INonfungiblePositionManager} from "@mgv-strats/src/strategies/vendor/monoswap/INonFungiblePositionManager.sol";
import {Forwarder} from "@mgv-strats/src/strategies/offer_forwarder/abstract/Forwarder.sol";

/// @title MonoswapMgvManager
/// @author Mangrove DAO
/// @notice This contract aims to manage the positions of a user on Monoswap
/// * Users can add and remove positions to update when using the MonoSwap Restaker Strategy on Mangrove
/// * These positions can be managed by the user or by designated managers
/// * Once the positions are added, the `isOk` function checks if using this strategy will work for the user.
contract MonoswapMgvManager {
  /// @notice The monoswap position manager contract
  INonfungiblePositionManager public immutable positionManager;

  /// @notice The forwarder contract (Mangrove Order)
  /// @dev Any forwarder able to compute the router address thanks to the general
  /// * `RouterProxyFoactory` can be used here
  Forwarder private immutable forwarder;

  /// @notice The positions of the users
  mapping(address => uint[]) private _positions;

  /// @notice The managers of the users
  mapping(address => mapping(address => bool)) public managers;

  /// @notice Emitted when a manager is added to a user
  /// @param user The user to add the manager to
  /// @param manager The manager to add
  event ManagerAdded(address indexed user, address indexed manager);

  /// @notice Emitted when a manager is removed from a user
  /// @param user The user to remove the manager from
  /// @param manager The manager to remove
  event ManagerRemoved(address indexed user, address indexed manager);

  /// @notice Emitted when a position is added to a user
  /// @param user The user to add the position to
  /// @param positionId The position to add
  event PositionAdded(address indexed user, uint indexed positionId);

  /// @notice Emitted when a position is removed from a user
  /// @param user The user to remove the position from
  /// @param positionId The position to remove
  event PositionRemoved(address indexed user, uint indexed positionId);

  /// @notice Constructor
  /// @param _positionManager The monoswap position manager contract
  /// @param _forwarder The forwarder contract (Mangrove Order)
  constructor(INonfungiblePositionManager _positionManager, Forwarder _forwarder) {
    positionManager = _positionManager;
    forwarder = _forwarder;
  }

  /// @notice Modifier to check if the user is allowed to manage the positions
  /// @param _user The user to check
  modifier onlyAllowed(address _user) {
    require(_user == msg.sender || managers[_user][msg.sender], "MonoswapManager/not-allowed");
    _;
  }

  /// @notice Add a manager to a user
  /// @param _user The user to add the manager to
  /// @param _manager The manager to add
  function addManager(address _user, address _manager) external onlyAllowed(_user) {
    managers[_user][_manager] = true;
    emit ManagerAdded(_user, _manager);
  }

  /// @notice Remove a manager from a user
  /// @param _user The user to remove the manager from
  /// @param _manager The manager to remove
  function removeManager(address _user, address _manager) external onlyAllowed(_user) {
    managers[_user][_manager] = false;
    emit ManagerRemoved(_user, _manager);
  }

  /// @notice Add a position to a user
  /// @param _user The user to add the position to
  /// @param _positionId The position to add
  function addPosition(address _user, uint _positionId) external onlyAllowed(_user) {
    _positions[_user].push(_positionId);
    emit PositionAdded(_user, _positionId);
  }

  /// @notice Add multiple positions to a user
  /// @param _user The user to add the positions to
  /// @param _positionIds The positions to add
  function addPositions(address _user, uint[] calldata _positionIds) external onlyAllowed(_user) {
    uint[] storage userPositions = _positions[_user];
    for (uint i = 0; i < _positionIds.length; i++) {
      userPositions.push(_positionIds[i]);
      emit PositionAdded(_user, _positionIds[i]);
    }
  }

  /// @notice Remove a position from a user
  /// @param _user The user to remove the position from
  /// @param _positionId The position to remove
  function removePosition(address _user, uint _positionId) external onlyAllowed(_user) {
    uint[] storage userPositions = _positions[_user];
    for (uint i = 0; i < userPositions.length; i++) {
      if (userPositions[i] == _positionId) {
        userPositions[i] = userPositions[userPositions.length - 1];
        userPositions.pop();
        emit PositionRemoved(_user, _positionId);
        return;
      }
    }
    revert("MonoswapManager/position-not-found");
  }

  function positions(address _user) external view returns (uint[] memory) {
    return _positions[_user];
  }

  /// @notice Checks if the strategy will succeed for each positions
  /// @param _user The user to check
  /// @return isOk True if the strategy will succeed
  function isOk(address _user) external view returns (bool) {
    uint[] memory userPositions = _positions[_user];
    if (userPositions.length == 0) {
      return true;
    }
    address router = address(forwarder.router(_user));
    if (positionManager.isApprovedForAll(_user, router)) {
      return true;
    }
    for (uint i = 0; i < userPositions.length; i++) {
      if (positionManager.getApproved(userPositions[i]) != router) {
        return false;
      }
    }
    return true;
  }
}
