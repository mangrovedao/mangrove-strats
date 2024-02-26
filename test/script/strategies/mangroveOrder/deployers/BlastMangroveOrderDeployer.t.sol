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
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";
import {Blast} from "@mgv/src/toy/blast/Blast.sol";

contract MangroveOrderDeployerTest is BaseMangroveOrderDeployerTest {
  function setUp() public {
    bytes memory creationCode = type(Blast).creationCode;
    bytes memory args = "";
    address where = address(BlastLib.BLAST);
    uint value = 0;
    vm.etch(where, abi.encodePacked(creationCode, args));
    (bool success, bytes memory runtimeBytecode) = where.call{value: value}("");
    require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
    vm.etch(where, runtimeBytecode);

    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    // this adds "Mangrove" and "RouterProxyFactory" to toyENS
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
    (new BlastRouterProxyFactoryDeployer()).innerRun();

    mgoDeployer = new BlastMangroveOrderDeployer();
  }
}
