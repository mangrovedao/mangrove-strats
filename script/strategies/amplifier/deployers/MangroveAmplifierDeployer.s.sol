// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
// import {MangroveOrder, IERC20, IMangrove, RouterProxyFactory} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {
  MangroveAmplifier,
  IMangrove,
  RouterProxyFactory,
  SmartRouter
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";

/*  Deploys a MangroveAmplifier instance
    First test:
 forge script --fork-url mumbai MangroveAmplifierDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveAmplifierDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveAmplifier

  You can specify a mangrove address with the MGV env var.*/
contract MangroveAmplifierDeployer is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      routerProxyFactory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory")),
      routerImplementation: SmartRouter(envAddressOrName("MANGROVEORDER_ROUTER", "SmartRouter"))
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove that MangroveAmplifier should operate on
   * @param routerProxyFactory The RouterProxyFactory that MangroveAmplifier should use
   * @param routerImplementation The router implementation that MangroveAmplifier should use
   */
  function innerRun(IMangrove mgv, RouterProxyFactory routerProxyFactory, SmartRouter routerImplementation) public {
    MangroveAmplifier mgvAmp;
    // Bug workaround: Foundry has a bug where the nonce is not incremented when MangroveAmplifier is deployed.
    //                 We therefore ensure that this happens.
    uint64 nonce = vm.getNonce(broadcaster());
    broadcast();
    // See MangroveAmplifierGasreqBaseTest description for calculation of the gasreq.
    if (forMultisig) {
      mgvAmp = new MangroveAmplifier{salt: salt}(mgv, routerProxyFactory, routerImplementation);
    } else {
      mgvAmp = new MangroveAmplifier(mgv, routerProxyFactory, routerImplementation);
    }
    // Bug workaround: See comment above `nonce` further up
    if (nonce == vm.getNonce(broadcaster())) {
      vm.setNonce(broadcaster(), nonce + 1);
    }

    fork.set("MangroveOrder", address(mgvAmp));
    smokeTest(mgvAmp, mgv);
  }

  function smokeTest(MangroveAmplifier mgvAmp, IMangrove mgv) internal view {
    require(mgvAmp.MGV() == mgv, "Incorrect Mangrove address");
  }
}
