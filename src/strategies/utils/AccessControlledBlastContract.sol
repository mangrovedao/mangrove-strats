// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv-strats/src/strategies/interfaces/IBlast.sol";
import "@mgv-strats/src/strategies/interfaces/IBlastPoints.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";

contract AccessControlledBlastContract is IBlastPoints, AccessControlled {
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

  constructor(address admin_) AccessControlled(admin_) {
    blastSetup();
  }

  function blastSetup() internal {
    BLAST.configureClaimableGas();
    BLAST.configureGovernor(admin());
  }

  function blastPointsAdmin() external view returns (address) {
    return admin();
  }
}
