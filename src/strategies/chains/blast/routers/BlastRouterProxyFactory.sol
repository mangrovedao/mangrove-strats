// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {BlastLib} from "@mgv-strats/src/strategies/vendor/blast/BlastLib.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IBlastPoints} from "@mgv-strats/src/strategies/vendor/blast/IBlastPoints.sol";

/// @title BlastRouterProxyFactory
/// @notice The Blast variant of RouterProxyFactory
contract BlastRouterProxyFactory is RouterProxyFactory, AccessControlled, IBlastPoints {
  /// @notice BlastRouterProxyFactory is a RouterProxyFactory with an admin
  /// @param _admin The address of the admin of `this` at the end of deployment
  constructor(address _admin) AccessControlled(_admin) {
    BlastLib.BLAST.configureGovernor(_admin);
  }

  /// @inheritdoc IBlastPoints
  function blastPointsAdmin() external view override returns (address) {
    return _admin;
  }
}
