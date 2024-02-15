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
import {Univ3Deployer} from "@mgv-strats/src/toy_strategies/utils/Univ3Deployer.sol";

contract Univ3Test is Test2, Univ3Deployer {
  function setUp() public {
    deployUniv3();
  }

  function test_deployFactory() public {
    console.log("factory", address(factory));
  }
}
