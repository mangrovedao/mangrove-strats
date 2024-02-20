// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";
import {
  SimpleAaveLogicDeployer,
  SimpleAaveLogic,
  IPoolAddressesProvider
} from "@mgv-strats/script/strategies/routing_logic/deployers/SimpleAaveLogicDeployer.s.sol";

import {IERC20} from "@mgv/lib/IERC20.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {PoolAddressProviderMock} from "@mgv-strats/script/toy/AaveMock.sol";

import {Test2} from "@mgv/lib/Test2.sol";

contract SimpleAaveLogicDeployerTest is Deployer, Test2 {
  SimpleAaveLogicDeployer salDeployer;
  address chief;
  IERC20 dai;
  IPoolAddressesProvider aaveAddressProvider;

  function setUp() public {
    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);

    IERC20 base = new TestToken(address(this), "BASE", "base", 18);
    IERC20 quote = new TestToken(address(this), "QUOTE", "quote", 18);

    dai = new TestToken(address(this), "Dai", "Dai", 18);
    aaveAddressProvider = IPoolAddressesProvider(
      address(new PoolAddressProviderMock(dynamic([address(dai), address(base), address(quote)])))
    );

    salDeployer = new SimpleAaveLogicDeployer();
  }

  function test_normal_deploy() public {
    uint interestRateMode = 2;

    salDeployer.innerRun({addressProvider: aaveAddressProvider, interestRateMode: interestRateMode});

    SimpleAaveLogic sal = SimpleAaveLogic(fork.get("SimpleAaveLogic"));

    assertEq(sal.INTEREST_RATE_MODE(), interestRateMode);
  }
}
