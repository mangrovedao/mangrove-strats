// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import {MangroveOffer, RL} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {Kandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

///@title The Kandel strat with geometric price progression.
contract BlastKandel is Kandel {
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  constructor(
    IMangrove mgv,
    OLKey memory olKeyBaseQuote,
    uint gasreq,
    IBlast blastContract,
    address blastGovernor,
    IBlastPoints blastPointsContract,
    address blastPointsOperator
  ) Kandel(mgv, olKeyBaseQuote, gasreq) {
    blastContract.configureClaimableGas();
    blastContract.configureGovernor(blastGovernor);
    blastPointsContract.configurePointsOperator(blastPointsOperator);
  }
}
