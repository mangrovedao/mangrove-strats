// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/ERC4626Router.sol";
import {ERC4626RouterDeployer} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626RouterDeployer.sol";
import {RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";

contract ERC4626RouterProxyDeployer is ERC4626RouterDeployer {
  ERC4626Router public immutable router;

  constructor() {
    router = new ERC4626Router();
  }

  function deployRouter() external override returns (ERC4626Router router) {
    router = ERC4626Router(address(new RouterProxy(router)));

    router.setAdmin(msg.sender);
  }
}
