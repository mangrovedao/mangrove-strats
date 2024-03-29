// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {Amplifier, IMangrove} from "@mgv-strats/src/toy_strategies/offer_maker/Amplifier.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {Test2} from "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/*  Deploys a Amplifier instance
    First test:
 ADMIN=$MUMBAI_PUBLIC_KEY forge script --fork-url mumbai AmplifierDeployer -vvv
    Then broadcast and verify:
 ADMIN=$MUMBAI_PUBLIC_KEY WRITE_DEPLOY=true forge script --fork-url mumbai AmplifierDeployer -vvv --broadcast --verify
    Remember to activate it using Activate*/
contract AmplifierDeployer is Deployer, Test2 {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: envAddressOrName("ADMIN"),
      base: IERC20(envAddressOrName("BASE", "WETH")),
      stable1: IERC20(envAddressOrName("STABLE1", "USDC")),
      stable2: IERC20(envAddressOrName("STABLE2", "DAI")),
      tickSpacing1: vm.envUint("TICK_SPACING1"),
      tickSpacing2: vm.envUint("TICK_SPACING2")
    });
  }

  /**
   * @param admin address of the admin on Amplifier after deployment
   * @param base address of the base on Amplifier after deployment
   * @param stable1 address of the first stable coin on Amplifier after deployment
   * @param stable2 address of the second stable coin on Amplifier after deployment
   * @param tickSpacing1 tick spacing for the first stable coin's market
   * @param tickSpacing2 tick spacing for the second stable coin's market
   */
  function innerRun(
    IMangrove mgv,
    address admin,
    IERC20 base,
    IERC20 stable1,
    IERC20 stable2,
    uint tickSpacing1,
    uint tickSpacing2
  ) public {
    try fork.get("Amplifier") returns (address payable old_amplifier_address) {
      Amplifier old_amplifier = Amplifier(old_amplifier_address);
      uint bal = mgv.balanceOf(old_amplifier_address);
      if (bal > 0) {
        broadcast();
        old_amplifier.withdrawFromMangrove(bal, payable(admin));
      }
      uint old_balance = old_amplifier.admin().balance;
      broadcast();
      old_amplifier.retractOffers(true);
      uint new_balance = old_amplifier.admin().balance;
      console.log("Retrieved ", new_balance - old_balance + bal, "WEIs from old deployment", address(old_amplifier));
    } catch {
      console.log("No existing Amplifier in ToyENS");
    }
    console.log("Deploying Amplifier...");
    broadcast();
    Amplifier amplifier = new Amplifier(mgv, base, stable1, stable2, tickSpacing1, tickSpacing2, admin);
    fork.set("Amplifier", address(amplifier));
    require(amplifier.MGV() == mgv, "Smoke test failed.");
    outputDeployment();
    console.log("Deployed!", address(amplifier));
    console.log("Activating Amplifier");
    AbstractRouter router = amplifier.router();

    broadcast();
    base.approve(address(router), type(uint).max);

    deal(amplifier.FUND_OWNER(), address(base), 1);
    vm.startPrank(address(amplifier));
    require(router.pull(RL.createOrder({token: base, fundOwner: amplifier.FUND_OWNER()}), 1, true) == 1, "Pullfailed");
    vm.stopPrank();
  }
}
