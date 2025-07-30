// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TakaraKandel} from "./TakaraKandel.sol";
import {GeometricKandel} from "../abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandelSeeder} from "../abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {TakaraLendRouter, IComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";
import {TakaraLendRouterDeployer} from "./TakaraLendRouterDeployer.sol";

/// @title TakaraLendKandel strat deployer.
/// @notice This contract deploys Kandel strategies that integrate with Takara Lend for yield generation
contract TakaraKandelSeeder is AbstractKandelSeeder {
  /// @notice a new Kandel with Takara Lend router has been deployed.
  /// @param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  /// @param baseQuoteOlKeyHash the hash of the base/quote offer list key. This is indexed so that RPC calls can filter on it.
  /// @param quoteBaseOlKeyHash the hash of the quote/base offer list key. This is indexed so that RPC calls can filter on it.
  /// @param takaraKandel the address of the deployed strat.
  /// @param reserveId the reserve identifier used for the router.
  /// @notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on, who the owner is and what reserve they use.
  event NewTakaraKandel(
    address indexed owner,
    bytes32 indexed baseQuoteOlKeyHash,
    bytes32 indexed quoteBaseOlKeyHash,
    address takaraKandel,
    address reserveId
  );

  /// @notice The router deployer contract
  TakaraLendRouterDeployer public immutable routerDeployer;

  /// @notice The comptroller contract
  IComptroller public immutable comptroller;

  /// @notice constructor for `TakaraKandelSeeder`. Initializes a `TakaraLendRouter` with this seeder as admin.
  /// @param mgv The Mangrove deployment.
  /// @param takaraKandelGasreq the total gasreq to use for executing a kandel offer
  /// @param _routerDeployer The address of the TakaraLendRouterDeployer contract
  constructor(
    IMangrove mgv,
    uint takaraKandelGasreq,
    TakaraLendRouterDeployer _routerDeployer,
    IComptroller _comptroller
  ) AbstractKandelSeeder(mgv, takaraKandelGasreq) {
    routerDeployer = _routerDeployer;
    comptroller = _comptroller;
  }

  /// @inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool liquiditySharing)
    internal
    override
    returns (GeometricKandel kandel)
  {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = liquiditySharing ? msg.sender : address(0);

    TakaraLendRouter router = _deployRouter();

    kandel = new TakaraKandel(
      MGV,
      olKeyBaseQuote,
      KANDEL_GASREQ,
      Direct.RouterParams({
        routerImplementation: router, // using Takara Lend router to source liquidity
        fundOwner: owner,
        strict: liquiditySharing
      })
    );
    // Allowing newly deployed Kandel to bind to the TakaraLendRouter
    router.bind(address(kandel));
    // Set the Kandel as router admin
    router.setAdmin(address(kandel));

    emit NewTakaraKandel(
      owner, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel), address(kandel)
    );
  }

  /// @notice Deploys a new instance of TakaraLendRouter using the router deployer
  /// @return The address of the newly deployed TakaraLendRouter.
  function _deployRouter() internal virtual returns (TakaraLendRouter) {
    return routerDeployer.deployRouter(comptroller);
  }
}
