// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ICauldronV4} from "../../vendor/abracadabra/interfaces/ICauldronV4.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title This contract provides a collection of lending capabilities with Abracadabra- to whichever contract inherits it
contract AbracadabraLender {
  ///@notice The Abracadabra cauldron retrieved from the cauldron provider.
  ICauldronV4 public immutable CAULDRON;

  /// @notice contract's constructor
  /// @param cauldron address of cauldron this lender is for
  constructor(ICauldronV4 cauldron) {
    CAULDRON = cauldron;
  }

  /// @notice allows this contract to approve the POOL to transfer some underlying asset on its behalf
  /// @dev this is a necessary step prior to supplying tokens to the POOL or to repay a debt
  /// @param token the underlying asset for which approval is required
  /// @param amount the approval amount
  function _approveLender(IERC20 token, uint amount) internal {
    TransferLib.approveToken(token, address(CAULDRON), amount);
  }

  /// @notice convenience function to obtain the overlying of a given asset
  /// @param asset the underlying asset
  /// @return aToken the overlying asset
  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = CAULDRON.collateral();
  }

  ///@notice redeems funds from the pool
  ///@param token the asset one is trying to redeem
  ///@param amount of assets one wishes to redeem
  ///@param to is the address where the redeemed assets should be transferred
  ///@param noRevert does not revert if redeem throws
  ///@return reason for revert from Abracadabra.
  ///@return redeemed the amount of asset that were transferred to `to`
  function _redeem(IERC20 token, uint amount, address to, bool noRevert)
    internal
    returns (bytes32 reason, uint redeemed)
  {
    if (amount != 0) {
      uint8[] memory actions = new uint8[](1);
      uint[] memory values = new uint[](1);
      bytes[] memory datas = new bytes[](1);
      try CAULDRON.cook(actions, values, datas) returns (uint value1, uint value2) {
        // redeemed = _redeemed; // Need to work out what value will be
      } catch Error(string memory _reason) {
        require(noRevert, _reason);
        reason = bytes32(bytes(_reason));
      } catch {
        require(noRevert, "AbraLender/withdrawReverted");
        reason = "AbraLender/withdrawReverted";
      }
    }
  }

  ///@notice supplies funds to the pool
  ///@param token the asset one is supplying
  ///@param amount of assets to be transferred to the pool
  ///@param onBehalf address of the account whose collateral is being supplied to and which will receive the overlying
  ///@param noRevert does not revert if supplies throws
  ///@return reason for revert from Abracadabra.
  function _supply(IERC20 token, uint amount, address onBehalf, bool noRevert) internal returns (bytes32) {
    if (amount == 0) {
      return bytes32(0);
    } else {
      uint8[] memory actions = new uint8[](1);
      uint[] memory values = new uint[](1);
      bytes[] memory datas = new bytes[](1);
      try CAULDRON.cook(actions, values, datas) {
        // (address(token), amount, onBehalf, 0) {
        return bytes32(0);
      } catch Error(string memory reason) {
        require(noRevert, reason);
        return bytes32(bytes(reason));
      } catch {
        require(noRevert, "AbraLender/supplyReverted");
        return "AbraLender/supplyReverted";
      }
    }
  }

  ///@notice verifies whether an asset can be supplied on pool
  ///@param asset the asset one wants to lend
  ///@return true if the asset can be supplied on pool
  function checkAsset(IERC20 asset) public view returns (bool) {
    IERC20 aToken = overlying(asset);
    return address(aToken) != address(0);
  }
}
