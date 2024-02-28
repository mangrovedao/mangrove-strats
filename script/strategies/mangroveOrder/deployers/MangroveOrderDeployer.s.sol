// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {MangroveOrder, IERC20, IMangrove, RouterProxyFactory} from "@mgv-strats/src/strategies/MangroveOrder.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder

  You can specify a mangrove address with the MGV env var.*/
contract MangroveOrderDeployer is Deployer {
  function run() public virtual {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster()),
      routerProxyFactory: RouterProxyFactory(envAddressOrName("ROUTER_PROXY_FACTORY", "RouterProxyFactory"))
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove that MangroveOrder should operate on
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(IMangrove mgv, address admin, RouterProxyFactory routerProxyFactory) public {
    // Bug workaround: Foundry has a bug where the nonce is not incremented when MangroveOrder is deployed.
    //                 We therefore ensure that this happens.
    uint64 nonce = vm.getNonce(broadcaster());

    // See MangroveOrderGasreqBaseTest description for calculation of the gasreq.
    SmartRouter routerImplementation = deployRouter();
    MangroveOrder mgvOrder = deployMangroveOrder(mgv, admin, routerProxyFactory, routerImplementation);

    broadcast();
    routerImplementation.bind(address(mgvOrder));

    // Bug workaround: See comment above `nonce` further up
    if (nonce == vm.getNonce(broadcaster())) {
      vm.setNonce(broadcaster(), nonce + 1);
    }

    fork.set("MangroveOrder", address(mgvOrder));
    fork.set("MangroveOrder-Router", address(mgvOrder.ROUTER_IMPLEMENTATION()));
    smokeTest(mgvOrder, mgv);
  }

  function deployRouter() internal virtual returns (SmartRouter router) {
    broadcast();
    if (forMultisig) {
      router = new SmartRouter{salt: salt}();
    } else {
      router = new SmartRouter();
    }
  }

  function deployMangroveOrder(
    IMangrove mgv,
    address admin,
    RouterProxyFactory routerProxyFactory,
    SmartRouter routerImplementation
  ) internal virtual returns (MangroveOrder mgvOrder) {
    broadcast();
    if (forMultisig) {
      mgvOrder = new MangroveOrder{salt: salt}({
        mgv: mgv,
        factory: routerProxyFactory,
        deployer: admin,
        routerImplementation: routerImplementation
      });
    } else {
      mgvOrder = new MangroveOrder({
        mgv: mgv,
        factory: routerProxyFactory,
        deployer: admin,
        routerImplementation: routerImplementation
      });
    }
  }

  function smokeTest(MangroveOrder mgvOrder, IMangrove mgv) internal view {
    require(mgvOrder.MGV() == mgv, "Incorrect Mangrove address");
  }
}
