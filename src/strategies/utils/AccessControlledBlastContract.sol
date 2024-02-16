// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv-strats/src/strategies/interfaces/IBlastPoints.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";
import {BlastGasAndYieldClaimable} from "@mgv-strats/src/strategies/utils/BlastGasAndYieldClaimable.sol";
import {BaseBlast} from "@mgv-strats/src/strategies/utils/BaseBlast.sol";

contract AccessControlledBlastContract is AccessControlled, BaseBlast, BlastGasAndYieldClaimable {
  constructor(address admin_) AccessControlled(admin_) BlastGasAndYieldClaimable(admin_) {}
}
