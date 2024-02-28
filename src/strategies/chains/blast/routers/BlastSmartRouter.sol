// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/// @title BlastSmartRouter
/// @notice The Blast variant of SmartRouter
contract BlastSmartRouter is SmartRouter {
  IBlast BLAST;

  /// @notice Contract's constructor
  /// @param blastContract the Blast contract to use for configuration of claimable yield and gas
  /// @param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  /// @param blastPointsOperator the operator to register on the BlastPoints contract
  /// @dev The Blast contract is configured to claimable gas, and the governor is set to the deployer
  /// @dev As the contract will not hold any funds,
  constructor(IBlast blastContract, IBlastPoints blastPointsContract, address blastPointsOperator) SmartRouter() {
    // Governor is set in _onAdminChange
    BLAST = blastContract;

    blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(msg.sender);

    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }

  /// @inheritdoc AccessControlled
  function _onAdminChange(address admin_) internal override {
    // This may be called during construction where BLAST is not yet set
    if (address(BLAST) != address(0)) {
      BLAST.configureGovernor(admin_);
    }
  }
}
