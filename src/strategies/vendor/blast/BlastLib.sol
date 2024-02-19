// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBlast} from "./IBlast.sol";

library BlastLib {
  IBlast constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
}