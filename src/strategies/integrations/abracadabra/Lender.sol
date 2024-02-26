// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ICauldronV4} from "../../vendor/abracadabra/interfaces/ICauldronV4.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbracadabraAddressProvider} from "./AddressProvider.sol";

/// @title This contract provides a collection of lending capabilities with Abracadabra- to whichever contract inherits it
contract AbracadabraLender {
  ///@notice The Abracadabra cauldron retrieved from the cauldron provider.
  AbracadabraAddressProvider public immutable ADDRESSES;

  /// @notice contract's constructor
  /// @param addressProvider address provider to allow for cauldron look up
  constructor(AbracadabraAddressProvider addressProvider) {
    ADDRESSES = addressProvider;
  }

  function cauldronFor(IERC20 token) public view returns (ICauldronV4) {
    return ICauldronV4(ADDRESSES.cauldrons(address(token)));
  }

  ///@notice fetches the balance of the overlying of the asset (always MIM)
  ///@param owner the balance owner
  ///@return balance of the overlying of the asset
  function overlyingBalanceOf(address owner) internal view returns (uint) {
    return IERC20(ADDRESSES.MIM()).balanceOf(owner);
  }

  /// @notice allows this contract to approve the cauldron to transfer some underlying asset on its behalf
  /// @dev this is a necessary step prior to supplying tokens to the cauldron
  /// @param token the underlying asset for which approval is required
  /// @param amount the approval amount
  function _approveLender(IERC20 token, uint amount) internal {
    TransferLib.approveToken(token, address(cauldronFor(token)), amount);
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
      uint8[] memory actions = new uint8[](2);
      actions[0] = 4; // ACTION_REMOVE_COLLATERAL
      actions[1] = 21; // ACTION_BENTO_WITHDRAW

      uint[] memory values = new uint[](2);
      values[0] = 0;
      values[1] = 0;

      bytes[] memory datas = new bytes[](2);
      datas[0] = abi.encode(amount, to);
      datas[1] = abi.encode(token, to, 0, amount);

      try cauldronFor(token).cook(actions, values, datas) returns (uint value1, uint value2) {
        redeemed = value1;
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
      uint8[] memory actions = new uint8[](3);
      actions[0] = 11; // ACTION_UPDATE_EXCHANGE_RATE // ?
      actions[1] = 20; // ACTION_BENTO_DEPOSIT
      actions[2] = 10; // ACTION_ADD_COLLATERAL

      uint[] memory values = new uint[](3);
      values[0] = 0;
      values[1] = msg.value; // Needs to be set for Native tokens only
      values[2] = 0;

      bytes[] memory datas = new bytes[](3);
      datas[0] = abi.encode(false, uint(0), uint(0));
      datas[1] = abi.encode(token, onBehalf, amount, 0);
      datas[2] = abi.encode(int(-2), onBehalf, true);

      try cauldronFor(token).cook(actions, values, datas) {
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
}
