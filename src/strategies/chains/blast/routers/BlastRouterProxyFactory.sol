// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RouterProxyFactory, RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";

/// @title BlastRouterProxyFactory
/// @notice The Blast variant of RouterProxyFactory
contract BlastRouterProxyFactory is RouterProxyFactory, AccessControlled {
  IBlast internal immutable blastContract;
  IBlastPoints internal immutable blastPointsContract;
  address internal immutable blastPointsOperator;

  /// @notice BlastRouterProxyFactory is a RouterProxyFactory with an admin
  /// @param _admin The address of the admin of `this` at the end of deployment
  /// @param _blastContract the Blast contract to use for configuration of claimable yield and gas
  /// @param blastGovernor the governor to register on the Blast contract
  /// @param _blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  /// @param _blastPointsOperator the operator to register on the BlastPoints contract
  /// @dev The Blast contract is configured to claimable yield and gas
  constructor(
    address _admin,
    IBlast _blastContract,
    address blastGovernor,
    IBlastPoints _blastPointsContract,
    address _blastPointsOperator
  ) AccessControlled(_admin) {
    blastContract = _blastContract;
    blastPointsContract = _blastPointsContract;
    blastPointsOperator = _blastPointsOperator;

    blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }

  /// @inheritdoc RouterProxyFactory
  /// @dev Deploys a BlastSmartRouter and initializes it with the Blast contract and the Blast Points contract
  function _afterDeployProxy(RouterProxy proxy, address user) internal override {
    BlastSmartRouter(address(proxy)).initialize(blastContract, user, blastPointsContract, blastPointsOperator);
  }
}
