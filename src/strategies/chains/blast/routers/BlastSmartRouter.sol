// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";

/// @title BlastSmartRouter
/// @notice The Blast variant of SmartRouter
contract BlastSmartRouter is SmartRouter {
  /// @notice Contract's constructor
  /// @param _forcedBinding the address of the contract that will be forced to be bound to this router.
  constructor(address _forcedBinding) SmartRouter(_forcedBinding) {}

  /// @inheritdoc AccessControlled
  function _onAdminChange(address admin_) internal override {
    BlastLib.BLAST.configureGovernor(admin_);
  }
}
