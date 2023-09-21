// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderWithPermit2, IERC20, IMangrove} from "mgv_strat_src/strategies/MangroveOrderWithPermit2.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrderWithPermit2 instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder

  You can specify a mangrove address with the MGV env var.*/
contract MangroveOrderWithPermit2Deployer is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      permit2: IPermit2(envAddressOrName("PERMIT2", "Permit2")),
      admin: envAddressOrName("MGV_GOVERNANCE", broadcaster())
    });
    outputDeployment();
  }

  /**
   * @param mgv The Mangrove that MangroveOrderWithPermit2 should operate on
   * @param admin address of the admin on MangroveOrderWithPermit2 after deployment
   */
  function innerRun(IMangrove mgv, IPermit2 permit2, address admin) public {
    MangroveOrderWithPermit2 mgvOrder;
    // Bug workaround: Foundry has a bug where the nonce is not incremented when MangroveOrderWithPermit2 is deployed.
    //                 We therefore ensure that this happens.
    uint64 nonce = vm.getNonce(broadcaster());
    broadcast();
    // test show MangroveOrderWithPermit2 can execute resting order using 105K (70K of simple router included)
    // so setting offer logic's gasreq to 35K is enough
    // we use 60K here in order to allow partial fills to repost on top of up to 5 identical offers.
    if (forMultisig) {
      mgvOrder = new MangroveOrderWithPermit2{salt:salt}(mgv, permit2, admin, 60_000);
    } else {
      mgvOrder = new MangroveOrderWithPermit2(mgv, permit2, admin, 60_000);
    }
    // Bug workaround: See comment above `nonce` further up
    if (nonce == vm.getNonce(broadcaster())) {
      vm.setNonce(broadcaster(), nonce + 1);
    }

    fork.set("MangroveOrderWithPermit2", address(mgvOrder));
    fork.set("MangroveOrderWithPermit2-Router", address(mgvOrder.router()));
    smokeTest(mgvOrder, mgv);
  }

  function smokeTest(MangroveOrderWithPermit2 mgvOrder, IMangrove mgv) internal view {
    require(mgvOrder.MGV() == mgv, "Incorrect Mangrove address");
  }
}
