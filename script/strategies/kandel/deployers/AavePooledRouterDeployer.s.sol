// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {AavePooledRouter, IERC20, RL} from "@mgv-strats/src/strategies/routers/integrations/AavePooledRouter.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

///@title  AavePooledRouter deployer
contract AavePooledRouterDeployer is Deployer {
  function run() public {
    innerRun({addressProvider: envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider")});
  }

  function innerRun(address addressProvider) public {
    broadcast();
    AavePooledRouter router = new AavePooledRouter(addressProvider);

    smokeTest(router);
  }

  function smokeTest(AavePooledRouter router) internal {
    IERC20 usdc = IERC20(fork.get("USDC"));
    usdc.approve(address(router), 1);

    vm.prank(broadcaster());
    router.bind(address(this));

    // call below should not revert
    router.checkList(RL.createOrder({token: usdc, amount: 1, reserveId: address(this)}), address(this));
  }
}
