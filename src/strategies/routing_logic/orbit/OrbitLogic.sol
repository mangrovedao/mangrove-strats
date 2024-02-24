// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrbitSpaceStation} from "@orbit-protocol/contracts/SpaceStation.sol";
import {AbstractRoutingLogic} from "../abstract/AbstractRoutingLogic.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {OrbitLogicStorage} from "./OrbitLogicStorage.sol";
import {OErc20} from "@orbit-protocol/contracts/OErc20.sol";
import {ExponentialNoError} from "@orbit-protocol/contracts/External/ExponentialNoError.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title OrbitLogic
/// @author Mangrove DAO
/// @notice Routing logic for Orbit protocol
/// @dev This contract only uses Oerc20 tokens because no native tokens can be passed as params
contract OrbitLogic is AbstractRoutingLogic, ExponentialNoError {
  /// @notice Storage for Orbit protocol
  OrbitLogicStorage public immutable orbitStorage;

  /// @notice Constructor
  /// @param _spaceStation OrbitSpaceStation contract
  constructor(OrbitSpaceStation _spaceStation) {
    // deploys and automatically sets up storage
    orbitStorage = new OrbitLogicStorage(_spaceStation);
  }

  /// @notice Get the overlying oToken for a given token
  /// @param token IERC20 token
  function overlying(IERC20 token) public view returns (OErc20 _overlying) {
    _overlying = orbitStorage.overlying(token);
    require(address(_overlying) != address(0), "OrbitLogic: Invalid token");
  }

  /// @inheritdoc AbstractRoutingLogic
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool)
    external
    virtual
    override
    returns (uint pulled)
  {
    OErc20 overlyingToken = overlying(token);
    // compute amout to be pulled (currently taking stored axchange rate and not the current one)
    Exp memory exchangeRate = Exp({mantissa: overlyingToken.exchangeRateStored()});
    uint toPull = div_(amount, exchangeRate);
    // Pull the amount of oTokens from the fundOwner
    require(
      TransferLib.transferTokenFrom(IERC20(address(overlyingToken)), fundOwner, address(this), toPull),
      "OrbitLogic: Transfer failed"
    );
    // redeem the oTokens to get the underlying tokens
    overlyingToken.redeem(toPull);
    // send the underlying tokens to the fundOwner
    pulled = token.balanceOf(address(this));
    require(TransferLib.transferToken(token, msg.sender, pulled), "OrbitLogic: Transfer failed");
  }

  /// @inheritdoc AbstractRoutingLogic
  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual override returns (uint pushed) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "OrbitLogic: Transfer failed");
    OErc20 overlyingToken = overlying(token);
    // mint the position
    overlyingToken.mint(amount);
    // send all minted oTokens to the fundOwner
    uint balance = overlyingToken.balanceOf(address(this));
    require(
      TransferLib.transferToken(IERC20(address(overlyingToken)), fundOwner, balance), "OrbitLogic: Transfer failed"
    );
    return amount;
  }

  /// @inheritdoc AbstractRoutingLogic
  function balanceLogic(IERC20 token, address fundOwner) external view virtual override returns (uint balance) {
    // when using balanceLogic, we can use this custom logic to get the balance
    // when modifying the state we can use the `balanceOfUnderlying` to accrue interest as well
    // same with exchange rate stored and the current exchange rate
    OErc20 overlyingToken = overlying(token);
    uint oTokenBalance = overlyingToken.balanceOf(fundOwner);
    Exp memory exchangeRate = Exp({mantissa: overlyingToken.exchangeRateStored()});
    return mul_ScalarTruncate(exchangeRate, oTokenBalance);
  }
}
