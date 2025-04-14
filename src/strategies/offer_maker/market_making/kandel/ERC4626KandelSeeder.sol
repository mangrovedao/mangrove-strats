// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626Kandel} from "./ERC4626Kandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/ERC4626Router.sol";
import {ERC4626RouterDeployer} from "./ERC4626RouterDeployer.sol";

///@title ERC4626Kandel strat deployer.
contract ERC4626KandelSeeder is AbstractKandelSeeder {
  ///@notice a new Kandel with ERC4626 router has been deployed.
  ///@param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  ///@param baseQuoteOlKeyHash the hash of the base/quote offer list key. This is indexed so that RPC calls can filter on it.
  ///@param quoteBaseOlKeyHash the hash of the quote/base offer list key. This is indexed so that RPC calls can filter on it.
  ///@param erc4626Kandel the address of the deployed strat.
  ///@param reserveId the reserve identifier used for the router.
  ///@notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on, who the owner is and what reserve they use.
  event NewERC4626Kandel(
    address indexed owner,
    bytes32 indexed baseQuoteOlKeyHash,
    bytes32 indexed quoteBaseOlKeyHash,
    address erc4626Kandel,
    address reserveId
  );

  /// @notice The router deployer contract
  ERC4626RouterDeployer public immutable routerDeployer;

  ///@notice constructor for `ERC4626KandelSeeder`. Initializes an `ERC4626Router` with this seeder as admin.
  ///@param mgv The Mangrove deployment.
  ///@param erc4626KandelGasreq the total gasreq to use for executing a kandel offer
  ///@param _routerDeployer The address of the ERC4626RouterDeployer contract
  constructor(IMangrove mgv, uint erc4626KandelGasreq, ERC4626RouterDeployer _routerDeployer)
    AbstractKandelSeeder(mgv, erc4626KandelGasreq)
  {
    routerDeployer = _routerDeployer;
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool liquiditySharing)
    internal
    override
    returns (GeometricKandel kandel)
  {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = liquiditySharing ? msg.sender : address(0);

    ERC4626Router router = _deployRouter();

    kandel = new ERC4626Kandel(
      MGV,
      olKeyBaseQuote,
      KANDEL_GASREQ,
      Direct.RouterParams({
        routerImplementation: router, // using ERC4626 router to source liquidity
        fundOwner: owner,
        strict: liquiditySharing
      })
    );
    // Allowing newly deployed Kandel to bind to the ERC4626Router
    router.bind(address(kandel));
    // Set the Kandel as router admin
    router.setAdmin(address(kandel));
    emit NewERC4626Kandel(
      owner, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel), address(kandel)
    );
  }

  ///@notice Deploys a new instance of ERC4626Router using the router deployer
  ///@return The address of the newly deployed ERC4626Router.
  function _deployRouter() internal virtual returns (ERC4626Router) {
    return routerDeployer.deployRouter();
  }
}
