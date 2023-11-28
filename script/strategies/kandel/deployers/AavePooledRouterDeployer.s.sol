// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {
  AavePooledRouter,
  IERC20,
  RL,
  IPoolAddressesProvider
} from "@mgv-strats/src/strategies/routers/integrations/AavePooledRouter.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";

///@title  AavePooledRouter deployer
contract AavePooledRouterDeployer is Deployer, Test2 {
  function run() public {
    innerRun({addressProvider: IPoolAddressesProvider(envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider"))});
  }

  function innerRun(IPoolAddressesProvider addressProvider) public {
    broadcast();
    AavePooledRouter router = new AavePooledRouter(addressProvider);

    smokeTest(router);
  }

  function smokeTest(AavePooledRouter router) internal {
    IERC20 usdc = IERC20(fork.get("USDC"));
    usdc.approve(address(router), 10);
    deal(address(this), address(usdc), 10);

    vm.startPrank(broadcaster());
    router.bind(address(this));
    router.pushAndSupply(usdc, 10, usdc, 0, address(this));
    vm.stopPrank();

    // call below should not revert
    require(5 == router.pull(RL.createOrder({token: usdc, fundOwner: address(this)}), 5, true), "pull failed!");
  }
}
