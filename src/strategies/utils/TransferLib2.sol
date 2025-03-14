// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";

/**
 * @dev Adapted from OpenZeppelin's SafeERC20 library
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol
 */
library TransferLib2 {
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
