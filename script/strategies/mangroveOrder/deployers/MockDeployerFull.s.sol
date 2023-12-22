// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {MangroveOrder} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {RouterProxyFactory} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

contract MockDeployerFull is Script {
  function run() external {
    uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address mgv = vm.envAddress("MGV");
    address deployer = vm.envAddress("DEPLOYER");
    vm.startBroadcast(deployerPrivateKey);
    RouterProxyFactory routerProxyFactory = new RouterProxyFactory();
    vm.stopBroadcast();
    vm.startBroadcast(deployerPrivateKey);
    MangroveOrder mangroveOrder =
      new MangroveOrder(IMangrove(payable(mgv)), routerProxyFactory, new SmartRouter(), deployer);
    vm.stopBroadcast();
  }
}
