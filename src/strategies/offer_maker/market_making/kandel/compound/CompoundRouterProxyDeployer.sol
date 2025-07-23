// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CompoundV2Router} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {CompoundRouterDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundRouterDeployer.sol";
import {RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";

/// @title Compound V2 Router Proxy Deployer
/// @notice Deploys CompoundV2Router instances as proxies to reduce deployment costs
/// @dev Uses a single router implementation with proxy pattern for gas efficiency
contract CompoundRouterProxyDeployer is CompoundRouterDeployer {
  /// @notice The router implementation contract that all proxies will delegate to
  CompoundV2Router public immutable ROUTER_IMPLEMENTATION;

  /// @notice Constructor deploys the router implementation
  constructor() {
    ROUTER_IMPLEMENTATION = new CompoundV2Router();
  }

  /// @notice Deploys a new CompoundV2Router as a proxy
  /// @return router The newly deployed CompoundV2Router proxy
  function deployRouter() external override returns (CompoundV2Router router) {
    router = CompoundV2Router(address(new RouterProxy(ROUTER_IMPLEMENTATION)));
    router.setAdmin(msg.sender);
  }
}
