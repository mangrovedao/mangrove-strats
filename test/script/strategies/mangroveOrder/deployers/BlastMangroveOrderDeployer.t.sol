// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";
import {
  BlastMangroveOrderDeployer,
  BlastMangroveOrder
} from "@mgv-strats/script/strategies/mangroveOrder/deployers/BlastMangroveOrderDeployer.s.sol";
import {BlastRouterProxyFactoryDeployer} from
  "@mgv-strats/script/strategies/routerProxyFactory/deployers/BlastRouterProxyFactoryDeployer.s.sol";

import {BaseMangroveOrderDeployerTest} from "./BaseMangroveOrderDeployer.t.sol";
import {BlastLib} from "@mgv-strats/src/strategies/vendor/blast/BlastLib.sol";

contract MangroveOrderDeployerTest is BaseMangroveOrderDeployerTest {
  function setUp() public {
    deployCodeTo("Blast.sol", address(BlastLib.BLAST));
    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    // this adds "Mangrove" and "RouterProxyFactory" to toyENS
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
    (new BlastRouterProxyFactoryDeployer()).innerRun(chief);

    mgoDeployer = new BlastMangroveOrderDeployer();
  }
}
