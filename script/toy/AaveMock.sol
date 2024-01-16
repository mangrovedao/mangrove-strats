// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {DataTypes} from "@mgv-strats/src/strategies/vendor/aave/v3/contracts/protocol/libraries/types/DataTypes.sol";
import {MintableERC20BLWithDecimals} from "@mgv/src/toy/MintableERC20BLWithDecimals.sol";
import {IPriceOracleGetter} from "@mgv-strats/src/strategies/vendor/aave/v3/contracts/interfaces/IPriceOracleGetter.sol";

contract RewardsControllerIshMock {
  function claimAllRewards(address[] calldata assets, address to)
    external
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {}
}

contract PoolMock {
  mapping(address => address) underlyingToOverlying;

  constructor(address[] memory underlyings) {
    for (uint i = 0; i < underlyings.length; i++) {
      MintableERC20BLWithDecimals underlying = MintableERC20BLWithDecimals(underlyings[i]);
      MintableERC20BLWithDecimals overlying = new MintableERC20BLWithDecimals(
        address(this),
        string.concat("a", underlying.name()),
        string.concat("a", underlying.symbol()),
        underlying.decimals()
      );

      underlyingToOverlying[underlyings[i]] = address(overlying);
    }
  }

  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
    if (useAsCollateral) emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
    else emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
  }

  function getReserveData(address asset) external view returns (DataTypes.ReserveData memory result) {
    result.aTokenAddress = underlyingToOverlying[asset];
  }

  function supply(address asset, uint amount, address onBehalfOf, uint16) external {
    MintableERC20BLWithDecimals(asset).transferFrom(msg.sender, address(this), amount);
    MintableERC20BLWithDecimals(underlyingToOverlying[asset]).mint(onBehalfOf, amount);
    uint gas = gasleft();
    while (gas - gasleft() < 75756) {
      // burn gas
    }
  }

  function withdraw(address asset, uint amount, address to) external returns (uint) {
    MintableERC20BLWithDecimals(underlyingToOverlying[asset]).burn(to, amount);
    MintableERC20BLWithDecimals(asset).transfer(to, amount);
    return 0;
  }
}

contract PriceOracleMock is IPriceOracleGetter {
  function BASE_CURRENCY() external pure override returns (address) {
    return address(0);
  }

  function BASE_CURRENCY_UNIT() external pure override returns (uint) {
    return 8;
  }

  function getAssetPrice(address) external pure override returns (uint) {
    return 1e8;
  }
}

contract PoolAddressProviderMock {
  address immutable POOL;
  address immutable INCENTIVES_CONTROLLER;
  address immutable PRICE_ORACLE;

  constructor(address[] memory underlyings) {
    POOL = address(new PoolMock(underlyings));
    INCENTIVES_CONTROLLER = address(new RewardsControllerIshMock());
    PRICE_ORACLE = address(new PriceOracleMock());
  }

  function getAddress(bytes32 id) external view returns (address ret) {
    if (id == keccak256("INCENTIVES_CONTROLLER")) {
      ret = INCENTIVES_CONTROLLER;
    } else if (id == "PRICE_ORACLE") {
      ret = PRICE_ORACLE;
    }
  }

  function getPool() external view returns (address) {
    return POOL;
  }
}
