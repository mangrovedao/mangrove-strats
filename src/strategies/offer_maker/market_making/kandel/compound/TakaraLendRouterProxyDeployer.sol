// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TakaraLendRouter, IComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";
import {TakaraLendRouterDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/TakaraLendRouterDeployer.sol";
import {RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";

/// @title Compound V2 Router Proxy Deployer
/// @notice Deploys TakaraLendRouter instances as proxies to reduce deployment costs
/// @dev Uses a single router implementation with proxy pattern for gas efficiency
contract TakaraLendRouterProxyDeployer is TakaraLendRouterDeployer {
  /// @notice The router implementation contract that all proxies will delegate to
  TakaraLendRouter public immutable ROUTER_IMPLEMENTATION;
  address public constant TAKARA_COMPTROLLER = 0x71034bf5eC0FAd7aEE81a213403c8892F3d8CAeE;

  /// @notice Constructor deploys the router implementation
  constructor() {
    ROUTER_IMPLEMENTATION = new TakaraLendRouter(IComptroller(TAKARA_COMPTROLLER));
  }

  /// @notice Deploys a new TakaraLendRouter as a proxy
  /// @return router The newly deployed TakaraLendRouter proxy
  function deployRouter(IComptroller) external override returns (TakaraLendRouter router) {
    router = TakaraLendRouter(address(new RouterProxy(ROUTER_IMPLEMENTATION)));
    router.setAdmin(msg.sender);
  }
}
