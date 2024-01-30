// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IBeefyVaultV7} from "@mgv-strats/src/strategies/vendor/beefy/IBeefyVaultV7.sol";
import {BeefyCommonLogic} from "@mgv-strats/src/strategies/routing_logic/beefy/BeefyCommonLogic.sol";

/**
 * @title SimpleBeefyLogic
 * @author Mangrove DAO
 * @notice This contract implements a simple routing logic for Beefy vaults
 * SimpleBeefyLogic supposedly treats vaults whose underlying tokens are directly supported by Mangrove
 */
contract SimpleBeefyLogic is AbstractRoutingLogic {
  /**
   * @notice The vault to pull from
   */
  IBeefyVaultV7 public immutable vault;

  /**
   * @notice The common logic implementation
   */
  BeefyCommonLogic public immutable commonLogic;

  /**
   * @notice Contract's constructor
   * @param _vault The vault to pull from
   * @param _commonLogic The common logic implementation
   */
  constructor(IBeefyVaultV7 _vault, BeefyCommonLogic _commonLogic) {
    vault = _vault;
    commonLogic = _commonLogic;
  }

  /**
   * @notice Propagates a revert with reason from a failed delegate call.
   * @param retdata The return data from the delegate call that caused the revert.
   * @dev This function uses inline assembly to revert with the exact error message from the delegate call.
   */
  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("SimpleBeefyLogic/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }

  /**
   * @notice delegate to the common logic
   * @param callData The call data to delegate to the common logic
   * @return retdata The return data from the delegate call
   */
  function delegateToCommonLogic(bytes memory callData) internal returns (bytes memory) {
    (bool success, bytes memory retdata) = address(commonLogic).delegatecall(callData);
    if (!success) {
      revertWithData(retdata);
    }
    return retdata;
  }

  /**
   * @inheritdoc AbstractRoutingLogic
   */
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict)
    external
    virtual
    override
    returns (uint pulled)
  {
    // pull using the common logic with the vault as parameter
    // We pass msg.sender because in the simple logic, the vault supposedly has a supported token as underlying
    bytes memory callData =
      abi.encodeWithSelector(commonLogic.pullLogic.selector, vault, msg.sender, token, fundOwner, amount, strict);
    return abi.decode(delegateToCommonLogic(callData), (uint));
  }

  /**
   * @inheritdoc AbstractRoutingLogic
   */
  function pushLogic(IERC20 token, address fundOwner, uint amount) external virtual override returns (uint pushed) {
    // push using the common logic with the vault as parameter
    // We pass msg.sender because in the simple logic, the vault supposedly has a supported token as underlying
    // so we can directly take funds from maker contract to deposit them on the vault
    bytes memory callData =
      abi.encodeWithSelector(commonLogic.pushLogic.selector, vault, msg.sender, token, fundOwner, amount);
    return abi.decode(delegateToCommonLogic(callData), (uint));
  }

  /**
   * @inheritdoc AbstractRoutingLogic
   */
  function balanceLogic(IERC20, address fundOwner) external view virtual override returns (uint balance) {
    balance = commonLogic.balanceLogic(vault, fundOwner);
  }
}
