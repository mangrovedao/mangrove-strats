// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {IBlastPoints} from "@mgv-strats/src/strategies/vendor/blast/IBlastPoints.sol";
import {BlastLib} from "@mgv-strats/src/strategies/vendor/blast/BlastLib.sol";
import {YieldMode, GasMode} from "@mgv-strats/src/strategies/vendor/blast/IBlast.sol";
import {MangroveAmplifier} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";

/// @title BlastMangroveAmplifier
/// @author Mangrove
/// @notice The Blast variant of MangroveAmplifier
contract BlastMangroveAmplifier is MangroveAmplifier, IBlastPoints {
  ///@notice MangroveAmplifier is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param routerImplementation the router implementation used to deploy user routers
  constructor(IMangrove mgv, RouterProxyFactory factory, BlastSmartRouter routerImplementation)
    MangroveAmplifier(mgv, factory, routerImplementation)
  {
    BlastLib.BLAST.configure(YieldMode.CLAIMABLE, GasMode.CLAIMABLE, msg.sender);
  }

  /// @inheritdoc IBlastPoints
  function blastPointsAdmin() external view override returns (address) {
    return _admin;
  }
}
