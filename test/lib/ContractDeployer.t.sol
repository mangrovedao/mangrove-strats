// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test2, toFixed, Test, console, toString, console, vm} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {ContractDeployer} from "@mgv-strats/src/toy_strategies/utils/ContractDeployer.sol";
import {RouterProxy, AbstractRouter} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";

contract ContractDeployer_Test is Test2 {
  function test_deployERC20() public {
    string memory json = vm.readFile("node_modules/@uniswap/v2-core/build/ERC20.json");
    string memory key = ".bytecode";
    bytes memory bytecode = vm.parseBytes(abi.decode(vm.parseJson(json, key), (string)));
    console.log("bytecode", vm.toString(bytecode));
    bytes memory bytecode2 = abi.decode(vm.parseJson(json, key), (bytes));
    console.log("bytecode2", vm.toString(bytecode2));
    uint totalSupply = 123;
    bytes memory args = abi.encode(totalSupply);
    address token = ContractDeployer.deployBytecodeWithArgs(bytecode, args);

    uint supply = IERC20(token).totalSupply();

    assertEq(supply, totalSupply);
  }

  function test_routerProxy() public {
    bytes memory bytecode = type(RouterProxy).creationCode;
    address routerProxy2 = ContractDeployer.deployBytecodeWithArgs(bytecode, abi.encode(address(3)));
    assertEq(address(RouterProxy(routerProxy2).IMPLEMENTATION()), address(3));
  }
}
