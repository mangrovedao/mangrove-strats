// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MangroveOrderDeployer} from "./MangroveOrderDeployer.s.sol";
import {Script, console} from "@mgv/forge-std/Script.sol";
import {IERC20, IMangrove, MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {BlastRouterProxyFactory} from "@mgv-strats/src/strategies/chains/blast/routers/BlastRouterProxyFactory.sol";
import {BlastMangroveOrder} from "@mgv-strats/src/strategies/chains/blast/BlastMangroveOrder.sol";

contract BlastMangroveOrderDeployer is MangroveOrderDeployer {
  function deployMangroveOrder(IMangrove mgv, address admin, BlastRouterProxyFactory routerProxyFactory)
    internal
    virtual
    returns (MangroveOrder mgvOrder)
  {
    if (forMultisig) {
      mgvOrder = new BlastMangroveOrder{salt: salt}(mgv, routerProxyFactory, admin);
    } else {
      mgvOrder = new BlastMangroveOrder(mgv, routerProxyFactory, admin);
    }
  }
}
