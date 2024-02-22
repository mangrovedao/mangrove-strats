// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";
import {MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";

/// @title BlastMangroveOrder
/// @author Mangrove
/// @notice The Blast variant of MangroveOrder
contract BlastMangroveOrder is MangroveOrder, IBlastPoints {
  ///@notice MangroveOrder is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param deployer The address of the admin of `this` at the end of deployment
  constructor(IMangrove mgv, RouterProxyFactory factory, address deployer) MangroveOrder(mgv, factory, deployer) {
    BlastLib.BLAST.configureGovernor(deployer);
  }

  /// @inheritdoc MangroveOrder
  function _deploySmartRouter() internal override returns (SmartRouter) {
    return new BlastSmartRouter(address(this));
  }

  /// @inheritdoc IBlastPoints
  function blastPointsAdmin() external view override returns (address) {
    return _admin;
  }
}
