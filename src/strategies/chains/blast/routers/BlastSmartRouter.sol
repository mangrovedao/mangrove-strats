// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/// @title BlastSmartRouter
/// @notice The Blast variant of SmartRouter
contract BlastSmartRouter is SmartRouter {
  /// @notice Whether the contract has been initialized
  bool public initialized;

  /// @notice Contract's constructor
  /// @param _forcedBinding the address of the contract that will be forced to be bound to this router.
  constructor(address _forcedBinding) SmartRouter(_forcedBinding) {}

  /// @notice Initializes the BlastSmartRouter with the Blast contract and the Blast Points contract
  /// @param blastContract the Blast contract to use for configuration of claimable yield and gas
  /// @param user the governor to register on the Blast contract
  /// @param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  /// @param blastPointsOperator the operator to register on the BlastPoints contract
  function initialize(IBlast blastContract, address user, IBlastPoints blastPointsContract, address blastPointsOperator)
    external
  {
    require(initialized == false, "BlastSmartRouter: already initialized");

    blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(user);

    blastPointsContract.configurePointsOperator(blastPointsOperator);

    _setAdmin(user);
  }
}
