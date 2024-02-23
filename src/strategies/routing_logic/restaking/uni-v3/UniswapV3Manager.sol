// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title Uniswap V3 Manager
/// @author Mangrove DAO
/// @notice This contract is used to manage Uniswap V3 positions used by the mangrove strategy
/// * This contract holds the position ID for the managed positions
/// * It also holds the balances of the tokens that cannot be reinvested immediately into the strategy
contract UniswapV3Manager is ERC1155("") {
  /// @notice The position manager contract
  INonfungiblePositionManager public immutable positionManager;

  /// @notice The router implementation contract
  AbstractRouter public immutable ROUTER_IMPLEMENTATION;

  /// @notice The router proxy factory contract
  RouterProxyFactory public immutable routerProxyFactory;

  /// @notice The positions mapping
  mapping(address owner => uint position) public positions;

  /// @notice Fires when a position is changed
  /// @param user the user address
  /// @param positionId the position ID
  event PositionChanged(address indexed user, uint indexed positionId);

  /// @notice Modifier to allow only the user or a manager to call a function
  /// @param _user the user address
  modifier onlyAllowed(address _user) {
    require(_user == msg.sender || isApprovedForAll(_user, msg.sender), "UniV3Manager/not-allowed");
    _;
  }

  /// @notice Modifier to allow only the user router to call a function
  /// @param _user the user address
  modifier onlyUserRouter(address _user) {
    require(userRouter(_user) == msg.sender, "UniV3Manager/not-allowed");
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

  /// @notice Returns the id corresponding to a token
  /// @param _token the token address
  /// @return _id the token id
  function id(IERC20 _token) internal pure returns (uint _id) {
    assembly {
      _id := _token
    }
  }

  /// @notice Returns the balance of a token
  /// @param _user the user address
  /// @param _token the token address
  /// @return _balance the token balance
  function balanceOf(address _user, IERC20 _token) public view returns (uint) {
    return balanceOf(_user, id(_token));
  }

  /// @notice Returns the full balances of a user given a list of tokens
  /// * Only non-zero balances are returned
  /// @param _user the user address
  /// @param _tokens the tokens addresses
  /// @return tokens the tokens with non-zero balances
  /// @return amounts the non-zero balances
  function getFullBalancesParams(address _user, IERC20[] calldata _tokens)
    external
    view
    returns (IERC20[] memory tokens, uint[] memory amounts)
  {
    uint[] memory _amounts = new uint[](_tokens.length);
    uint nTokens;
    for (uint i = 0; i < _tokens.length; i++) {
      _amounts[i] = balanceOf(_user, _tokens[i]);
      if (_amounts[i] > 0) {
        nTokens++;
      }
    }

    tokens = new IERC20[](nTokens);
    amounts = new uint[](nTokens);

    uint j;
    for (uint i = 0; i < _tokens.length; i++) {
      if (_amounts[i] > 0) {
        tokens[j] = _tokens[i];
        amounts[j] = _amounts[i];
        j++;
      }
    }
  }

  /// @notice Returns the user router address
  /// @param _user the user address
  /// @return router the user router address
  function userRouter(address _user) public view returns (address) {
    return routerProxyFactory.computeProxyAddress(_user, ROUTER_IMPLEMENTATION);
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
    if (_amount == 0) {
      return;
    }
    require(balanceOf(_user, _token) >= _amount, "UniV3Manager/insufficient-balance");
    require(TransferLib.transferToken(_token, _destination, _amount), "UniV3Manager/transfer-failed");
  }

  /// @notice Retracts the balance of a token
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _amount the amount retracted from the balance
  /// @param _destination the destination address
  function _retractBalanceSingle(address _user, IERC20 _token, uint _amount, address _destination) internal {
    _retractBalance(_user, _token, _amount, _destination);
    _burn(_user, id(_token), _amount);
  }

  /// @notice Retracts the balance of a token
  /// @param _user the user address
  /// @param _tokens the tokens retracted from the balance
  /// @param _amounts the amounts retracted from the balance
  /// @param _destination the destination address
  function _batchRetractBalance(
    address _user,
    IERC20[] calldata _tokens,
    uint[] calldata _amounts,
    address _destination
  ) internal {
    uint[] memory _ids = new uint[](_tokens.length);
    for (uint i = 0; i < _tokens.length; i++) {
      _ids[i] = id(_tokens[i]);
      _retractBalance(_user, _tokens[i], _amounts[i], _destination);
    }
    _burnBatch(_user, _ids, _amounts);
  }

  // -- User balances functions --

  /// @notice Retracts the balance of a token
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _destination the destination address
  function retractBalance(address _user, IERC20 _token, address _destination) external onlyAllowed(_user) {
    _retractBalanceSingle(_user, _token, balanceOf(_user, _token), _destination);
  }

  /// @notice Retracts an amount of a token from the balance
  /// @param _user the user address
  /// @param _token the token retracted from the balance
  /// @param _amount the amount retracted from the balance
  /// @param _destination the destination address
  function retractAmount(address _user, IERC20 _token, uint _amount, address _destination) external onlyAllowed(_user) {
    _retractBalanceSingle(_user, _token, _amount, _destination);
  }

  /// @notice Retracts an amount of a token from the balance
  /// @param _user the user address
  /// @param _tokens the token retracted from the balance
  /// @param _amounts the amount retracted from the balance
  /// @param _destination the destination address
  function retractAmounts(address _user, IERC20[] calldata _tokens, uint[] calldata _amounts, address _destination)
    external
    onlyAllowed(_user)
  {
    _batchRetractBalance(_user, _tokens, _amounts, _destination);
  }

  // -- router functions --

  /// @notice Adds to the balance of a token
  /// @param _user the user address
  /// @param _tokens the tokens added to the balance
  /// @param _amounts the amounts added to the balance
  function addToBalances(address _user, IERC20[] calldata _tokens, uint[] calldata _amounts)
    external
    onlyUserRouter(_user)
  {
    uint toMint;
    for (uint i = 0; i < _tokens.length; i++) {
      IERC20 _token = _tokens[i];
      uint _amount = _amounts[i];
      if (_amount == 0) {
        continue;
      }
      toMint++;
      require(TransferLib.transferTokenFrom(_token, msg.sender, address(this), _amount), "UniV3Manager/transfer-failed");
    }
    if (toMint == 0) {
      return;
    }
    uint[] memory ids = new uint[](toMint);
    uint[] memory amounts = new uint[](toMint);
    uint j;

    for (uint i = 0; i < _tokens.length; i++) {
      if (_amounts[i] > 0) {
        ids[j] = id(_tokens[i]);
        amounts[j] = _amounts[i];
        j++;
      }
    }

    _mintBatch(_user, ids, amounts, "");
  }

  /// @notice Takes an amount from the balance of a token to a destination
  /// @param _user the user address
  /// @param _tokens the tokens taken from the balance
  /// @param _amounts the amounts taken from the balance
  /// @param _destination the destination address
  function routerTakeAmounts(address _user, IERC20[] calldata _tokens, uint[] calldata _amounts, address _destination)
    external
    onlyUserRouter(_user)
  {
    _batchRetractBalance(_user, _tokens, _amounts, _destination);
  }
}
