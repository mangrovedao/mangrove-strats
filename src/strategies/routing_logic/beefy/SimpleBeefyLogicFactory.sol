// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BeefyCommonLogic, SimpleBeefyLogic, IERC20, IBeefyVaultV7} from "./SimpleBeefyLogic.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";

/**
 * @title SimpleBeefyLogicFactory
 * @author Mangrove DAO
 * @notice This contract deploys SimpleBeefyLogic contracts
 */
contract SimpleBeefyLogicFactory is AccessControlled(msg.sender) {
  /**
   * @notice The common logic implementation
   */
  BeefyCommonLogic public immutable commonLogic;

  /**
   * @notice Maps every token to a list of logics deployed for that token
   */
  mapping(IERC20 token => SimpleBeefyLogic[]) public logicsForToken;

  /**
   * @notice Contract's constructor
   */
  constructor() {
    commonLogic = new BeefyCommonLogic();
  }

  /**
   * @notice Deploys a new SimpleBeefyLogic contract for a given vault
   * @param vault The vault to pull from
   */
  function addLogic(IBeefyVaultV7 vault) public onlyAdmin {
    // use create2 to ensure that the logic is not already deployed
    bytes32 salt = keccak256(abi.encodePacked(vault));
    SimpleBeefyLogic logic = new SimpleBeefyLogic{salt: salt}(vault, commonLogic);
    logicsForToken[vault.want()].push(logic);
  }

  /**
   * @notice Deploys several new SimpleBeefyLogic contracts for a list of vaults
   * @param vaults The vaults to pull from
   */
  function addLogics(IBeefyVaultV7[] calldata vaults) external onlyAdmin {
    for (uint i = 0; i < vaults.length; i++) {
      addLogic(vaults[i]);
    }
  }
}
