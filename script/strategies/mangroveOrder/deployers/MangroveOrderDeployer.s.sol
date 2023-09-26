// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {MangroveOrder, IERC20, IMangrove} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateBaseMangroveOrder

  You can specify a mangrove address with the MGV env var.*/
contract MangroveOrderDeployer is Deployer {
  function run() public {
    innerRun({
      permit2: IPermit2(envAddressOrName("PERMIT2", "Permit2")),
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster())
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove that MangroveOrder should operate on
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(IPermit2 permit2, IMangrove mgv, address admin) public {
    MangroveOrder mgvOrder;
    // Bug workaround: Foundry has a bug where the nonce is not incremented when MangroveOrder is deployed.
    //                 We therefore ensure that this happens.
    uint64 nonce = vm.getNonce(broadcaster());
    broadcast();
    // test show MangroveOrder can execute resting order using 105K (70K of simple router included)
    // so setting offer logic's gasreq to 35K is enough
    // we use 60K here in order to allow partial fills to repost on top of up to 5 identical offers.
    if (forMultisig) {
      mgvOrder = new MangroveOrder{salt:salt}(permit2, mgv, admin, 60_000);
    } else {
      mgvOrder = new MangroveOrder(permit2, mgv, admin, 60_000);
    }
    // Bug workaround: See comment above `nonce` further up
    if (nonce == vm.getNonce(broadcaster())) {
      vm.setNonce(broadcaster(), nonce + 1);
    }

    fork.set("MangroveOrder", address(mgvOrder));
    fork.set("MangroveOrder-Router", address(mgvOrder.router()));
    smokeTest(mgvOrder, mgv);
  }

  function smokeTest(MangroveOrder mgvOrder, IMangrove mgv) internal view {
    require(mgvOrder.MGV() == mgv, "Incorrect Mangrove address");
  }
}
