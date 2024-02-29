// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {MangroveAmplifier} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

/// @title BlastMangroveAmplifier
/// @author Mangrove
/// @notice The Blast variant of MangroveAmplifier
contract BlastMangroveAmplifier is MangroveAmplifier {
  ///@notice MangroveAmplifier is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param routerImplementation the router implementation used to deploy user routers
  ///@param blastContract the Blast contract to use for configuration of claimable yield and gas
  ///@param blastGovernor the governor to register on the Blast contract
  ///@param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  ///@param blastPointsOperator the operator to register on the BlastPoints contract
  ///@dev The Blast contract is configured to claimable yield and gas
  constructor(
    IMangrove mgv,
    RouterProxyFactory factory,
    BlastSmartRouter routerImplementation,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) MangroveAmplifier(mgv, factory, routerImplementation) {
    // blastContract.configureClaimableYield();
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }
}
