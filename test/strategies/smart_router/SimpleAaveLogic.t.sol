// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MgvOrder_Test} from "../MgvOrder.t.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";

contract SimpleAaveLogicTest is MgvOrder_Test {
  IPoolAddressesProvider public aave;

  function bootstrapStrats() internal virtual override {
    aave = IPoolAddressesProvider(fork.get("AaveAddressProvider"));
    super.bootstrapStrats();
  }
}
