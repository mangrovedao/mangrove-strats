// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/TransferLib.sol";

/// @title TransferLib2
/// @notice an extension of Mangrove's TransferLib
library TransferLib2 {
  ///@notice This transfer amount of token to recipient address
  ///@param token Token to be transferred
  ///@param recipient Address of the recipient the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function transferToken(IERC20 token, address recipient, uint amount) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    if (recipient == address(this)) {
      return token.balanceOf(recipient) >= amount;
    }
    return _transferToken(token, recipient, amount);
  }

  ///@notice This transfer amount of token to recipient address
  ///@param token Token to be transferred
  ///@param recipient Address of the recipient the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function _transferToken(IERC20 token, address recipient, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if any since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.transfer.selector, recipient, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice This transfer amount of token to recipient address from spender address
  ///@param token Token to be transferred
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function transferTokenFrom(IERC20 token, address spender, address recipient, uint amount) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    if (spender == recipient) {
      return token.balanceOf(spender) >= amount;
    }
    // optimization to avoid requiring contract to approve itself
    if (spender == address(this)) {
      return _transferToken(token, recipient, amount);
    }
    return _transferTokenFrom(token, spender, recipient, amount);
  }

  ///@notice This transfer amount of token to recipient address from spender address
  ///@param token Token to be transferred
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function _transferTokenFrom(IERC20 token, address spender, address recipient, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if there since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.transferFrom.selector, spender, recipient, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice ERC20 approval, handling non standard approvals that do not return a value
  ///@param token the ERC20
  ///@param spender the address whose allowance is to be given
  ///@param amount of the allowance
  ///@return true if approval was successful; otherwise, false.
  function _approveToken(IERC20 token, address spender, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if any since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice ERC20 approval, handling non standard approvals that do not return a value
  ///@param token the ERC20
  ///@param spender the address whose allowance is to be given
  ///@param amount of the allowance
  ///@return true if approval was successful; otherwise, false.
  function approveToken(IERC20 token, address spender, uint amount) internal returns (bool) {
    return _approveToken(token, spender, amount);
  }

  /// @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
  /// non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
  /// to be set to zero before setting it to a non-zero value, such as USDT.
  ///
  /// NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
  /// only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
  /// set here.
  function forceApproveToken(IERC20 token, address spender, uint value) internal returns (bool) {
    bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

    if (!_callOptionalReturnBool(token, approvalCall)) {
      if (!_callOptionalReturnBool(token, abi.encodeCall(token.approve, (spender, 0)))) return false;
      return _callOptionalReturnBool(token, approvalCall);
    }
    return true;
  }

  /// @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
  /// on the return value: the return value is optional (but if data is returned, it must not be false).
  /// @param token The token targeted by the call.
  /// @param data The call data (encoded using abi.encode or one of its variants).
  ///
  /// This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
  function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
    bool success;
    uint returnSize;
    uint returnValue;
    assembly ("memory-safe") {
      success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
      returnSize := returndatasize()
      returnValue := mload(0)
    }
    return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
  }
}
