// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";
import {
  MangroveOrderDeployer,
  MangroveOrder
} from "@mgv-strats/script/strategies/mangroveOrder/deployers/MangroveOrderDeployer.s.sol";
import {RouterProxyFactoryDeployer} from
  "@mgv-strats/script/strategies/routerProxyFactory/deployers/RouterProxyFactoryDeployer.s.sol";

import {BaseMangroveOrderDeployerTest} from "./BaseMangroveOrderDeployer.t.sol";

contract MangroveOrderDeployerTest is BaseMangroveOrderDeployerTest {
  function setUp() public {
    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    // this adds "Mangrove" and "RouterProxyFactory" to toyENS
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
    (new RouterProxyFactoryDeployer()).innerRun();

    mgoDeployer = new MangroveOrderDeployer();
  }
}
