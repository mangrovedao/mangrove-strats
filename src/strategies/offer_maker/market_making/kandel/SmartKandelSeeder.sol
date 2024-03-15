// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SmartKandel} from "./SmartKandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

///@title SmartKandel strat deployer.
contract SmartKandelSeeder is AbstractKandelSeeder {
  ///@notice The factory for creating router proxies.
  RouterProxyFactory public immutable PROXY_FACTORY;

  ///@notice The implementation of the router to use.
  AbstractRouter internal immutable ROUTER_IMPLEMENTATION;

  ///@notice a new Kandel has been deployed.
  ///@param owner the owner of the strat. This is indexed so that RPC calls can filter on it.
  ///@param baseQuoteOlKeyHash the hash of the base/quote offer list key. This is indexed so that RPC calls can filter on it.
  ///@param quoteBaseOlKeyHash the hash of the quote/base offer list key. This is indexed so that RPC calls can filter on it.
  ///@param kandel the address of the deployed strat.
  ///@notice By emitting this data, an indexer will be able to keep track of what Kandel strats are deployed, what market its deployed on and who the owner is.
  event NewSmartKandel(
    address indexed owner, bytes32 indexed baseQuoteOlKeyHash, bytes32 indexed quoteBaseOlKeyHash, address kandel
  );

  ///@notice constructor for `KandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers.
  ///@param factory the router proxy factory contract.
  ///@param routerImplementation the deployed SmartRouter contract used to generate proxys for offer owners.
  constructor(IMangrove mgv, uint kandelGasreq, RouterProxyFactory factory, AbstractRouter routerImplementation)
    AbstractKandelSeeder(mgv, kandelGasreq)
  {
    PROXY_FACTORY = factory;
    ROUTER_IMPLEMENTATION = routerImplementation;
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(OLKey memory olKeyBaseQuote, bool) internal virtual override returns (GeometricKandel kandel) {
    kandel = new SmartKandel(MGV, olKeyBaseQuote, KANDEL_GASREQ, msg.sender, PROXY_FACTORY, ROUTER_IMPLEMENTATION);
    emit NewSmartKandel(msg.sender, olKeyBaseQuote.hash(), olKeyBaseQuote.flipped().hash(), address(kandel));
  }
}
