// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrbitSpaceStation} from "@orbit-protocol/contracts/SpaceStation.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {OToken} from "@orbit-protocol/contracts/OToken.sol";
import {OErc20} from "@orbit-protocol/contracts/OErc20.sol";
import {ComptrollerV2Storage} from "@orbit-protocol/contracts/Core/ComptrollerStorage.sol";

/// @title OrbitLogicStorage
/// @author Mangrove DAO
/// @notice Maps underlying tokens to their corresponding cTokens
contract OrbitLogicStorage {
  /// @notice Mapping from underlying tokens to their corresponding cTokens
  mapping(IERC20 token => OErc20 oToken) public overlying;

  /// @notice OrbitSpaceStation contract
  OrbitSpaceStation public immutable spaceStation;

  /// @notice Constructor
  /// @param _spaceStation OrbitSpaceStation contract
  constructor(OrbitSpaceStation _spaceStation) {
    spaceStation = _spaceStation;
    setUpStorage();
  }

  /// @notice Set up storage
  function setUpStorage() public {
    OToken[] memory cTokens = spaceStation.getAllMarkets();
    for (uint i = 0; i < cTokens.length; i++) {
      OErc20 cToken = OErc20(address(cTokens[i]));
      try cToken.underlying() returns (address underlying) {
        overlying[IERC20(underlying)] = cToken;
      } catch {
        continue;
      }
    }
  }

  /// @notice Remove a market
  /// @param token IERC20 token
  function removeMarket(IERC20 token) public {
    // do checks first
    OErc20 cToken = overlying[token];
    OToken[] memory cTokens = spaceStation.getAllMarkets();
    for (uint i = 0; i < cTokens.length; i++) {
      if (cTokens[i] == OToken(address(cToken))) {
        revert("Market is still in use");
      }
    }
    delete overlying[token];
  }

  /// @notice Remove multiple markets
  /// @param tokens IERC20 tokens
  function removeMarkets(IERC20[] memory tokens) public {
    OToken[] memory cTokens = spaceStation.getAllMarkets();
    for (uint i = 0; i < tokens.length; i++) {
      OErc20 cToken = overlying[tokens[i]];
      for (uint j = 0; j < cTokens.length; j++) {
        if (cTokens[j] == OToken(address(cToken))) {
          revert("Market is still in use");
        }
      }
      delete overlying[tokens[i]];
    }
  }
}
