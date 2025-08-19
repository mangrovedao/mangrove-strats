// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CompoundKandel} from "./CompoundKandel.sol";
import {GeometricKandel} from "../abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandelSeeder} from "../abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {CompoundRouterDeployer} from "./CompoundRouterDeployer.sol";

/// @title CompoundKandel strat deployer.
/// @notice This contract deploys Kandel strategies that integrate with Compound V2 for yield generation
contract CompoundKandelSeeder is AbstractKandelSeeder {
  /// @notice a new Kandel with Compound V2 router has been deployed.
  /// @param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  /// @param baseQuoteOlKeyHash the hash of the base/quote offer list key. This is indexed so that RPC calls can filter on it.
  /// @param quoteBaseOlKeyHash the hash of the quote/base offer list key. This is indexed so that RPC calls can filter on it.
  /// @param compoundKandel the address of the deployed strat.
  /// @param reserveId the reserve identifier used for the router.
  /// @notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on, who the owner is and what reserve they use.
  event NewCompoundKandel(
    address indexed owner,
    bytes32 indexed baseQuoteOlKeyHash,
    bytes32 indexed quoteBaseOlKeyHash,
    address compoundKandel,
    address reserveId
  );

  /// @notice The router deployer contract
  CompoundRouterDeployer public immutable routerDeployer;

  /// @notice constructor for `CompoundKandelSeeder`. Initializes a `CompoundV2Router` with this seeder as admin.
  /// @param mgv The Mangrove deployment.
  /// @param compoundKandelGasreq the total gasreq to use for executing a kandel offer
  /// @param _routerDeployer The address of the CompoundRouterDeployer contract
  constructor(IMangrove mgv, uint compoundKandelGasreq, CompoundRouterDeployer _routerDeployer)
    AbstractKandelSeeder(mgv, compoundKandelGasreq)
  {
    routerDeployer = _routerDeployer;
  }

  /// @inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool liquiditySharing)
    internal
    virtual
    override
    returns (GeometricKandel kandel)
  {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = liquiditySharing ? msg.sender : address(0);

    AbstractRouter router = _deployRouter();

    kandel = new CompoundKandel(
      MGV,
      olKeyBaseQuote,
      KANDEL_GASREQ,
      Direct.RouterParams({
        routerImplementation: router, // using Compound V2 router to source liquidity
        fundOwner: owner,
        strict: liquiditySharing
      })
    );
    // Allowing newly deployed Kandel to bind to the CompoundV2Router
    router.bind(address(kandel));
    // Set the Kandel as router admin
    router.setAdmin(address(kandel));
    emit NewCompoundKandel(
      msg.sender, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel), address(kandel)
    );
  }

  /// @notice Deploys a new instance of AbstractRouter using the router deployer
  /// @return The address of the newly deployed AbstractRouter.
  function _deployRouter() internal virtual returns (AbstractRouter) {
    return routerDeployer.deployRouter();
  }
}
