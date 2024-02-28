// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/// @title BlastRouterProxyFactory
/// @notice The Blast variant of RouterProxyFactory
contract BlastRouterProxyFactory is RouterProxyFactory, AccessControlled {
  /// @notice BlastRouterProxyFactory is a RouterProxyFactory with an admin
  /// @param _admin The address of the admin of `this` at the end of deployment
  /// @param blastContract the Blast contract to use for configuration of claimable yield and gas
  /// @param blastGovernor the governor to register on the Blast contract
  /// @param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  /// @param blastPointsOperator the operator to register on the BlastPoints contract
  /// @dev The Blast contract is configured to claimable yield and gas
  constructor(
    address _admin,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) AccessControlled(_admin) {
    blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);

    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }
}
