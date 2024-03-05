// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import {Kandel} from "./Kandel.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {BlastKandel} from "./BlastKandel.sol";
import {KandelSeeder} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

///@title Kandel strat deployer.
contract BlastKandelSeeder is KandelSeeder {
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
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) KandelSeeder(mgv, kandelGasreq) {
    _blastContract = blastContract;
    _blastGovernor = blastGovernor;
    _blastPointsContract = blastPointsContract;
    _blastPointsOperator = blastPointsOperator;

    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    // blastPointsContract.configurePointsOperator(blastPointsOperator);
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool) internal override returns (GeometricKandel kandel) {
    kandel = new BlastKandel(
      MGV, olKeyBaseQuote, KANDEL_GASREQ, _blastContract, _blastGovernor, _blastPointsContract, _blastPointsOperator
    );
    emit NewKandel(msg.sender, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel));
  }
}
