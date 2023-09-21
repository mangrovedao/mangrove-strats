// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MangroveOrderDeployer} from "mgv_strat_script/strategies/mangroveOrder/deployers/MangroveOrderDeployer.s.sol";
import {MangroveOrderWithPermit2Deployer} from
  "mgv_strat_script/strategies/mangroveOrder/deployers/MangroveOrderWithPermit2Deployer.s.sol";
import {KandelSeederDeployer} from "mgv_strat_script/strategies/kandel/deployers/KandelSeederDeployer.s.sol";
import {MangroveOrder} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {MangroveOrderWithPermit2} from "mgv_strat_src/strategies/MangroveOrderWithPermit2.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {SimpleTestMaker} from "mgv_test/lib/agents/TestMaker.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {ActivateMarket} from "mgv_script/core/ActivateMarket.s.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "lib/permit2/test/utils/DeployPermit2.sol";
import {PoolAddressProviderMock} from "mgv_strat_script/toy/AaveMock.sol";
import "forge-std/console.sol";

/* 
This script prepares a local server for testing by mangrove.js.

In the future it should a) Use mostly the normal deploy file, so there is as
little discrepancy between real deploys and deploys that mangrove.js tests
interact with.  b) For any additional deployments needed, those files should be
hosted in mangrove.js.*/

contract MangroveJsDeploy is Deployer {
  TestToken public tokenA;
  TestToken public tokenB;
  IERC20 public dai;
  IERC20 public usdc;
  IERC20 public weth;
  SimpleTestMaker public simpleTestMaker;
  IPermit2 public permit2;

  function run() public {
    innerRun({gasprice: 1, gasmax: 2_000_000, gasbot: broadcaster()});
    outputDeployment();
  }

  function innerRun(uint gasprice, uint gasmax, address gasbot) public {
    DeployPermit2 deployPermit2 = new DeployPermit2();
    permit2 = IPermit2(deployPermit2.deployPermit2()); // deploy permit2 using the precompiled bytecode

    MangroveDeployer mgvDeployer = new MangroveDeployer();

    mgvDeployer.innerRun({chief: broadcaster(), gasprice: gasprice, gasmax: gasmax, gasbot: gasbot});

    Mangrove mgv = mgvDeployer.mgv();
    MgvReader mgvReader = mgvDeployer.reader();

    broadcast();
    mgv.setUseOracle(false);

    broadcast();
    tokenA = new TestToken({
      admin: broadcaster(),
      name: "Token A",
      symbol: "TokenA",
      _decimals: 18
    });

    broadcast();
    tokenA.setMintLimit(type(uint).max);
    fork.set("TokenA", address(tokenA));

    broadcast();
    tokenB = new TestToken({
      admin: broadcaster(),
      name: "Token B",
      symbol: "TokenB",
      _decimals: 6
    });

    broadcast();
    tokenB.setMintLimit(type(uint).max);
    fork.set("TokenB", address(tokenB));

    broadcast();
    dai = new TestToken({
      admin: broadcaster(),
      name: "DAI",
      symbol: "DAI",
      _decimals: 18
    });
    fork.set("DAI", address(dai));

    broadcast();
    usdc = new TestToken({
      admin: broadcaster(),
      name: "USD Coin",
      symbol: "USDC",
      _decimals: 6
    });
    fork.set("USDC", address(usdc));

    broadcast();
    weth = new TestToken({
      admin: broadcaster(),
      name: "Wrapped Ether",
      symbol: "WETH",
      _decimals: 18
    });
    fork.set("WETH", address(weth));

    broadcast();
    simpleTestMaker = new SimpleTestMaker({
      _mgv: AbstractMangrove(payable(mgv)),
      _base: tokenA,
      _quote: tokenB
    });
    fork.set("SimpleTestMaker", address(simpleTestMaker));

    ActivateMarket activateMarket = new ActivateMarket();

    activateMarket.innerRun(mgv, mgvReader, tokenA, tokenB, 2 * 1e9, 3 * 1e9, 0);
    activateMarket.innerRun(mgv, mgvReader, dai, usdc, 1e9 / 1000, 1e9 / 1000, 0);
    activateMarket.innerRun(mgv, mgvReader, weth, dai, 1e9, 1e9 / 1000, 0);
    activateMarket.innerRun(mgv, mgvReader, weth, usdc, 1e9, 1e9 / 1000, 0);

    MangroveOrderDeployer mgoeDeployer = new MangroveOrderDeployer();
    mgoeDeployer.innerRun({admin: broadcaster(), mgv: IMangrove(payable(mgv))});

    MangroveOrderWithPermit2Deployer mgoeWithPermit2Deployer = new MangroveOrderWithPermit2Deployer();
    mgoeWithPermit2Deployer.innerRun({admin: broadcaster(), mgv: IMangrove(payable(mgv)), permit2: permit2});

    address[] memory underlying =
      dynamic([address(tokenA), address(tokenB), address(dai), address(usdc), address(weth)]);
    broadcast();
    address aaveAddressProvider = address(new PoolAddressProviderMock(underlying));

    KandelSeederDeployer kandelSeederDeployer = new KandelSeederDeployer();
    kandelSeederDeployer.innerRun({
      mgv: IMangrove(payable(mgv)),
      addressesProvider: aaveAddressProvider,
      aaveRouterGasreq: 318_000,
      aaveKandelGasreq: 338_000,
      kandelGasreq: 128_000
    });

    broadcast();
  }
}
