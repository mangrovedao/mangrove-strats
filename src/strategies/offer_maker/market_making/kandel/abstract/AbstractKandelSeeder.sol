// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {GeometricKandel} from "./GeometricKandel.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs, OLKey} from "mgv_src/MgvLib.sol";

///@title Abstract Kandel strat deployer.
///@notice This seeder deploys Kandel strats on demand and binds them to an AAVE router if needed.
///@dev deployer of this contract will gain aave manager power on the AAVE router (power to claim rewards and enter/exit markets)
///@dev when deployer is a contract one must therefore make sure it is able to call the corresponding functions on the router
abstract contract AbstractKandelSeeder {
  ///@notice The Mangrove deployment.
  IMangrove public immutable MGV;
  ///@notice the gasreq to use for offers.
  uint public immutable KANDEL_GASREQ;

  ///@notice constructor for `AbstractKandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers
  constructor(IMangrove mgv, uint kandelGasreq) {
    MGV = mgv;
    KANDEL_GASREQ = kandelGasreq;
  }

  ///@notice a new Kandel with pooled AAVE router has been deployed.
  ///@param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  ///@param olKeyHash the hash of the offer list key. This is indexed so that RPC calls can filter on it.
  ///@param aaveKandel the address of the deployed strat.
  ///@param reserveId the reserve identifier used for the router.
  ///@notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on, who the owner is and what reserve they use.
  event NewAaveKandel(address indexed owner, bytes32 indexed olKeyHash, address aaveKandel, address reserveId);

  ///@notice a new Kandel has been deployed.
  ///@param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  ///@param olKeyHash the hash of the offer list key. This is indexed so that RPC calls can filter on it.
  ///@param kandel the address of the deployed strat.
  ///@notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on and who the owner is.
  event NewKandel(address indexed owner, bytes32 indexed olKeyHash, address kandel);

  ///@notice Kandel deployment parameters
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasprice one wants to use for Kandel's provision
  ///@param liquiditySharing if true, `msg.sender` will be used to identify the shares of the deployed Kandel strat. If msg.sender deploys several instances, reserve of the strats will be shared, but this will require a transfer from router to maker contract for each taken offer, since we cannot transfer the full amount to the first maker contract hit in a market order in case later maker contracts need the funds. Still, only a single AAVE redeem will take place.
  struct KandelSeed {
    OLKey olKeyBaseQuote;
    uint gasprice;
    bool liquiditySharing;
  }

  ///@notice deploys a new Kandel contract for the given seed.
  ///@param seed the parameters for the Kandel strat
  ///@return kandel the Kandel contract.
  function sow(KandelSeed calldata seed) external returns (GeometricKandel kandel) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller

    (, MgvStructs.LocalPacked local) = MGV.config(seed.olKeyBaseQuote);
    (, MgvStructs.LocalPacked local_) = MGV.config(seed.olKeyBaseQuote.flipped());

    require(local.active() && local_.active(), "KandelSeeder/inactiveMarket");

    kandel = _deployKandel(seed);
    kandel.setAdmin(msg.sender);
  }

  ///@notice deploys a new Kandel contract for the given seed.
  ///@param seed the parameters for the Kandel strat
  ///@return kandel the Kandel contract.
  function _deployKandel(KandelSeed calldata seed) internal virtual returns (GeometricKandel kandel);
}
