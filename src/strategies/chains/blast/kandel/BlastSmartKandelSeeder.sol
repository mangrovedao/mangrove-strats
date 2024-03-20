// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {BlastSmartKandel} from "./BlastSmartKandel.sol";
import {
  SmartKandelSeeder,
  RouterProxyFactory,
  AbstractRouter
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/SmartKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

///@title Kandel strat deployer.
contract BlastSmartKandelSeeder is SmartKandelSeeder {
  /// @notice a new Kandel has been deployed.
  address internal immutable _blastGovernor;

  ///@notice constructor for `KandelSeeder`.
  IBlast internal immutable _blastContract;

  /// @notice BlastRouterProxyFactory is a RouterProxyFactory with an admin
  IBlastPoints internal immutable _blastPointsContract;

  /// @notice BlastRouterProxyFactory is a RouterProxyFactory with an admin
  address internal immutable _blastPointsOperator;

  ///@notice constructor for `KandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers.
  ///@param blastContract the Blast contract to use for configuration of claimable yield and gas
  ///@param blastGovernor the governor to register on the Blast contract
  ///@param blastPointsContract the BlastPoints contract on which to register the Blast Points operator
  ///@param blastPointsOperator the operator to register on the BlastPoints contract
  constructor(
    IMangrove mgv,
    uint kandelGasreq,
    RouterProxyFactory factory,
    AbstractRouter routerImplementation,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) SmartKandelSeeder(mgv, kandelGasreq, factory, routerImplementation) {
    _blastContract = blastContract;
    _blastGovernor = blastGovernor;
    _blastPointsContract = blastPointsContract;
    _blastPointsOperator = blastPointsOperator;

    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool) internal override returns (GeometricKandel kandel) {
    kandel = new BlastSmartKandel(
      MGV,
      olKeyBaseQuote,
      KANDEL_GASREQ,
      msg.sender,
      PROXY_FACTORY,
      ROUTER_IMPLEMENTATION,
      _blastContract,
      _blastGovernor,
      _blastPointsContract,
      _blastPointsOperator
    );
    emit NewSmartKandel(msg.sender, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel));
  }
}
