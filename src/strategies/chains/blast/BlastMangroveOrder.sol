// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

import {RenegingForwarder} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";

/// @title BlastMangroveOrder
/// @author Mangrove
/// @notice The Blast variant of MangroveOrder
contract BlastMangroveOrder is MangroveOrder {
  IBlast internal _blast;

  ///@notice MangroveOrder is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param deployer The address of the admin of `this` at the end of deployment
  ///@param blastContract the Blast contract to use for configuration of claimable yield and gas
  ///@param blastGovernor the governor to register on the Blast contract
  ///@param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  ///@param blastPointsOperator the operator to register on the BlastPoints contract
  ///@dev The Blast contract is configured to claimable yield and gas
  constructor(
    IMangrove mgv,
    RouterProxyFactory factory,
    address deployer,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) MangroveOrder(mgv, factory, deployer) {
    // blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }

  /// @inheritdoc MangroveOrder
  function _deploySmartRouter() internal override returns (SmartRouter) {
    return new SmartRouter(address(this));
  }
}
