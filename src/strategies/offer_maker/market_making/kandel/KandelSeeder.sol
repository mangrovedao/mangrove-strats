// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Kandel} from "./Kandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

///@title Kandel strat deployer.
contract KandelSeeder is AbstractKandelSeeder {
  ///@notice a new Kandel has been deployed.
  ///@param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  ///@param olKeyHash the hash of the offer list key. This is indexed so that RPC calls can filter on it.
  ///@param kandel the address of the deployed strat.
  ///@notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on and who the owner is.
  event NewKandel(address indexed owner, bytes32 indexed olKeyHash, address kandel);

  ///@notice constructor for `KandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers.
  constructor(IMangrove mgv, uint kandelGasreq) AbstractKandelSeeder(mgv, kandelGasreq) {}

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool) internal override returns (GeometricKandel kandel) {
    kandel = new Kandel(MGV, olKeyBaseQuote, KANDEL_GASREQ, address(0));
    emit NewKandel(msg.sender, olKeyBaseQuote.hash(), address(kandel));
  }
}
