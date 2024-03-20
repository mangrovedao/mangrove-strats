// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test2, toFixed, Test, console, toString, vm} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {ContractDeployer} from "@mgv-strats/src/toy_strategies/utils/ContractDeployer.sol";
import {RouterProxy, AbstractRouter} from "@mgv-strats/src/strategies/routers/RouterProxy.sol";
import {IUniswapV3Factory} from "@mgv-strats/src/strategies/vendor/uniswap/v3/core/interfaces/IUniswapV3Factory.sol";
import {IWETH9} from "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/external/IWETH9.sol";
import {INonfungibleTokenPositionDescriptor} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungibleTokenPositionDescriptor.sol";
import {INonfungiblePositionManager} from
  "@mgv-strats/src/strategies/vendor/uniswap/v3/periphery/interfaces/INonfungiblePositionManager.sol";

contract Univ3Deployer {
  IUniswapV3Factory public factory;
  IWETH9 public weth9;
  INonfungibleTokenPositionDescriptor public tokenDescriptor;
  INonfungiblePositionManager public positionManager;

  function deployFactory() private {
    string memory content = vm.readFile("uni-out/UniswapV3Factory.txt");
    bytes memory bytecode = vm.parseBytes(content);
    factory = IUniswapV3Factory(ContractDeployer.deployFromBytecode(bytecode));
  }

  function deployeWETH9() private {
    // TODO
  }

  function deployTokenDescriptor() private {
    string memory content = vm.readFile("uni-out/NonfungibleTokenPositionDescriptor.txt");
    bytes memory bytecode = vm.parseBytes(content);
    bytes32 nativeCurrencyLabel = "ETH";
    bytes memory args = abi.encode(address(weth9), nativeCurrencyLabel);
    tokenDescriptor = INonfungibleTokenPositionDescriptor(ContractDeployer.deployBytecodeWithArgs(bytecode, args));
  }

  function deployPositionManager() private {
    string memory content = vm.readFile("uni-out/NonfungiblePositionManager.txt");
    bytes memory bytecode = vm.parseBytes(content);
    bytes memory args = abi.encode(address(factory), address(weth9), address(tokenDescriptor));
    positionManager = INonfungiblePositionManager(ContractDeployer.deployBytecodeWithArgs(bytecode, args));
  }

  function deployUniv3() public {
    deployFactory();
    deployeWETH9();
    deployTokenDescriptor();
    deployPositionManager();
  }
}
