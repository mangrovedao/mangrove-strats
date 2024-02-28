// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2, Test} from "@mgv/lib/Test2.sol";

import {MangroveDeployer, IMangrove} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";

import {
  MangroveOrderDeployer,
  MangroveOrder
} from "@mgv-strats/script/strategies/mangroveOrder/deployers/BlastMangroveOrderDeployer.s.sol";
import {
  BlastMangroveOrderDeployer,
  BlastMangroveOrder,
  BlastRouterProxyFactory
} from "@mgv-strats/script/strategies/mangroveOrder/deployers/BlastMangroveOrderDeployer.s.sol";
import {BlastRouterProxyFactoryDeployer} from
  "@mgv-strats/script/strategies/routerProxyFactory/deployers/BlastRouterProxyFactoryDeployer.s.sol";

import {BaseMangroveOrderDeployerTest} from "./BaseMangroveOrderDeployer.t.sol";
import {Blast} from "@mgv/src/toy/blast/Blast.sol";
import {BlastPoints} from "@mgv/src/toy/blast/BlastPoints.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

contract BlastMangroveOrderDeployerTest is Deployer, Test2 {
  BlastMangroveOrderDeployer mgoDeployer;
  address chief;

  function setUp() public {
    bytes memory creationCode = type(Blast).creationCode;
    bytes memory args = "";
    address blastAddress = freshAddress("Blast");
    uint value = 0;
    vm.etch(blastAddress, abi.encodePacked(creationCode, args));
    (bool success, bytes memory runtimeBytecode) = blastAddress.call{value: value}("");
    require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
    vm.etch(blastAddress, runtimeBytecode);
    fork.set("Blast", blastAddress);

    address blastPointsAddress = freshAddress("BlastPoints");
    creationCode = type(BlastPoints).creationCode;
    value = 0;
    vm.etch(blastPointsAddress, abi.encodePacked(creationCode, args));
    (success, runtimeBytecode) = blastPointsAddress.call{value: value}("");
    require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
    vm.etch(blastPointsAddress, runtimeBytecode);
    fork.set("BlastPoints", blastPointsAddress);

    chief = freshAddress("admin");
    address blastGovernor = freshAddress("BlastGovernor");
    address blastPointsOperator = freshAddress("BlastPointsOperator");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    // this adds "Mangrove" and "RouterProxyFactory" to toyENS
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
    (new BlastRouterProxyFactoryDeployer()).innerRun({
      admin: chief,
      _blastContract: IBlast(blastAddress),
      _blastPointsContract: IBlastPoints(blastPointsAddress),
      _blastGovernor: blastGovernor,
      _blastPointsOperator: blastPointsOperator
    });

    mgoDeployer = new BlastMangroveOrderDeployer();
  }

  function test_normal_deploy() public {
    // MangroveOrder - verify mgv is used and admin is chief
    address mgv = fork.get("Mangrove");
    mgoDeployer.innerRun({
      mgv: IMangrove(payable(mgv)),
      admin: chief,
      routerProxyFactory: BlastRouterProxyFactory(fork.get("RouterProxyFactory")),
      _blastContract: IBlast(fork.get("Blast")),
      _blastGovernor: freshAddress("BlastGovernor"),
      _blastPointsContract: IBlastPoints(fork.get("BlastPoints")),
      _blastPointsOperator: freshAddress("BlastPointsOperator")
    });
    MangroveOrder mgoe = MangroveOrder(fork.get("MangroveOrder"));
    address mgvOrderRouter = fork.get("MangroveOrder-Router");

    assertEq(mgoe.admin(), chief);
    assertEq(address(mgoe.MGV()), mgv);
    assertEq(address(mgoe.ROUTER_IMPLEMENTATION()), mgvOrderRouter);
  }
}
