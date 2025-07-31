// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TakaraKandel} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/takara/TakaraKandel.sol";
import {TakaraRouterProxyDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/takara/TakaraRouterProxyDeployer.sol";
import {CompoundKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

contract TakaraKandelSeeder is CompoundKandelSeeder {
  /// @notice a new Kandel with Takara router has been deployed.
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

  constructor(IMangrove mgv, uint compoundKandelGasreq, TakaraRouterProxyDeployer _routerDeployer)
    CompoundKandelSeeder(mgv, compoundKandelGasreq, _routerDeployer)
  {}

  function _deployKandel(OLKey memory olKeyBaseQuote, bool liquiditySharing)
    internal
    override
    returns (GeometricKandel kandel)
  {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = liquiditySharing ? msg.sender : address(0);

    AbstractRouter router = _deployRouter();

    kandel = new TakaraKandel(
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
    emit NewTakaraKandel(
      msg.sender, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel), address(kandel)
    );
  }
}
