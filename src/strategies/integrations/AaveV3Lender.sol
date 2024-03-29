// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPool} from "../vendor/aave/v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "../vendor/aave/v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IRewardsController} from "../vendor/aave/v3/periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title This contract provides a collection of lending capabilities with AAVE-v3 to whichever contract inherits it
contract AaveV3Lender {
  ///@notice The AAVE pool retrieved from the pool provider.
  IPool public immutable POOL;
  ///@notice The AAVE pool address provider.
  IPoolAddressesProvider public immutable ADDRESS_PROVIDER;

  /// @notice contract's constructor
  /// @param addressesProvider address of AAVE's address provider
  constructor(IPoolAddressesProvider addressesProvider) {
    ADDRESS_PROVIDER = addressesProvider;

    address lendingPool = IPoolAddressesProvider(addressesProvider).getPool();
    require(lendingPool != address(0), "AaveV3Lender/0xPool");

    POOL = IPool(lendingPool);
  }

  /// @notice allows this contract to approve the POOL to transfer some underlying asset on its behalf
  /// @dev this is a necessary step prior to supplying tokens to the POOL or to repay a debt
  /// @param token the underlying asset for which approval is required
  /// @param amount the approval amount
  function _approveLender(IERC20 token, uint amount) internal {
    TransferLib.approveToken(token, address(POOL), amount);
  }

  /// @notice prevents the POOL from using some underlying as collateral
  /// @dev this call will revert if removing the asset from collateral would put the account into a liquidation state
  /// @param underlying the token one wishes to remove collateral
  function _exitMarket(IERC20 underlying) internal {
    POOL.setUserUseReserveAsCollateral(address(underlying), false);
  }

  /// @notice allows the POOL to use some underlying tokens as collateral
  /// @dev when supplying a token for the first time, it is automatically set as possible collateral so there is no need to call this function for it.
  /// @param underlyings the token one wishes to add as collateral
  function _enterMarkets(IERC20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; ++i) {
      POOL.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  /// @notice convenience function to obtain the overlying of a given asset
  /// @param asset the underlying asset
  /// @return aToken the overlying asset
  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = IERC20(POOL.getReserveData(address(asset)).aTokenAddress);
  }

  ///@notice redeems funds from the pool
  ///@param token the asset one is trying to redeem
  ///@param amount of assets one wishes to redeem
  ///@param to is the address where the redeemed assets should be transferred
  ///@param noRevert does not revert if redeem throws
  ///@return reason for revert from Aave.
  ///@return redeemed the amount of asset that were transferred to `to`
  function _redeem(IERC20 token, uint amount, address to, bool noRevert)
    internal
    returns (bytes32 reason, uint redeemed)
  {
    if (amount != 0) {
      try POOL.withdraw(address(token), amount, to) returns (uint _redeemed) {
        redeemed = _redeemed;
      } catch Error(string memory _reason) {
        require(noRevert, _reason);
        reason = bytes32(bytes(_reason));
      } catch {
        require(noRevert, "AaveV3Lender/withdrawReverted");
        reason = "AaveV3Lender/withdrawReverted";
      }
    }
  }

  ///@notice supplies funds to the pool
  ///@param token the asset one is supplying
  ///@param amount of assets to be transferred to the pool
  ///@param onBehalf address of the account whose collateral is being supplied to and which will receive the overlying
  ///@param noRevert does not revert if supplies throws
  ///@return reason for revert from Aave.
  function _supply(IERC20 token, uint amount, address onBehalf, bool noRevert) internal returns (bytes32) {
    if (amount == 0) {
      return bytes32(0);
    } else {
      try POOL.supply(address(token), amount, onBehalf, 0) {
        return bytes32(0);
      } catch Error(string memory reason) {
        require(noRevert, reason);
        return bytes32(bytes(reason));
      } catch {
        require(noRevert, "AaveV3Lender/supplyReverted");
        return "AaveV3Lender/supplyReverted";
      }
    }
  }

  ///@notice rewards claiming.
  ///@param assets list of overlying for which one is claiming awards
  ///@param to whom the rewards should be sent
  ///@return rewardsList the address of assets that have been claimed
  ///@return claimedAmounts the amount of assets that have been claimed
  function _claimRewards(address[] calldata assets, address to)
    internal
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    IRewardsController rewardsController =
      IRewardsController(ADDRESS_PROVIDER.getAddress(keccak256("INCENTIVES_CONTROLLER")));
    (rewardsList, claimedAmounts) = rewardsController.claimAllRewards(assets, to);
  }

  ///@notice verifies whether an asset can be supplied on pool
  ///@param asset the asset one wants to lend
  ///@return true if the asset can be supplied on pool
  function checkAsset(IERC20 asset) public view returns (bool) {
    IERC20 aToken = overlying(asset);
    return address(aToken) != address(0);
  }
}
