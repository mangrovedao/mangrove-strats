// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MgvOrder_Test} from "../MgvOrder.t.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {AaveV3Lender} from "@mgv-strats/src/strategies/integrations/AaveV3Lender.sol";

contract SimpleAaveLogicTest is MgvOrder_Test {
  AaveV3Lender public aaveLender;

  function bootstrapStrats() internal virtual override {
    aaveLender = new AaveV3Lender(fork.get("AaveAddressProvider"));
    super.bootstrapStrats();
  }
}
