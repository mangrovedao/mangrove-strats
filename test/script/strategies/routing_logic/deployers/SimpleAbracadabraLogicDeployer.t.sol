// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";
import {
  SimpleAbracadabraLogicDeployer,
  SimpleAbracadabraLogic
} from "@mgv-strats/script/strategies/routing_logic/deployers/SimpleAbracadabraLogicDeployer.s.sol";

import {IERC20} from "@mgv/lib/IERC20.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {PoolAddressProviderMock} from "@mgv-strats/script/toy/AbracadabraMock.sol";
import {ICauldronV4} from "@mgv-strats/src/strategies/vendor/abracadabra/interfaces/ICauldronV4.sol";

import {Test2} from "@mgv/lib/Test2.sol";

contract SimpleAbracadabraLogicDeployerTest is Deployer, Test2 {
  SimpleAbracadabraLogicDeployer salDeployer;
  address chief;
  IERC20 dai;

  function setUp() public {
    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);

    IERC20 base = new TestToken(address(this), "BASE", "base", 18);
    IERC20 quote = new TestToken(address(this), "QUOTE", "quote", 18);

    dai = new TestToken(address(this), "Dai", "Dai", 18);
    salDeployer = new SimpleAbracadabraLogicDeployer();
  }

  function test_normal_deploy() public {
    salDeployer.innerRun({mim: dai, cauldron: ICauldronV4(address(0))});

    SimpleAbracadabraLogic sal = SimpleAbracadabraLogic(fork.get("SimpleAbracadabraLogic"));
  }
}
