// SPDX-License-Identifier:	MIT
pragma solidity ^0.8.20;

import {RenegingForwarder} from "./RenegingForwarder.sol";
import {
  MangroveOffer,
  Forwarder,
  IMangrove,
  RouterProxyFactory,
  RouterProxy,
  AbstractRouter,
  MgvLib,
  IERC20,
  OLKey
} from "./abstract/Forwarder.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {DelegatedRFLib} from "./DelegatedRFLib.sol";

contract DelegatedRenegingForwarder is RenegingForwarder {
  ///@notice Same as Forwarder's constructor
  ///@param mgv the deployed Mangrove contract on which this contract will post offers -- will revert if 0x
  ///@param factory the router proxy factory contract -- will revert if 0x
  ///@param routerImplementation the deployed SmartRouter contract used to generate proxys for offer owners -- will revert if 0x
  constructor(IMangrove mgv, RouterProxyFactory factory, AbstractRouter routerImplementation)
    RenegingForwarder(mgv, factory, routerImplementation)
  {}

  function internalNewOffer(OfferArgs memory args, address owner) external returns (uint offerId, bytes32 status) {
    return _newOffer(args, owner);
  }

  function internalUpdateOffer(OfferArgs memory args, uint offerId) external returns (bytes32 reason) {
    return _updateOffer(args, offerId);
  }
}
