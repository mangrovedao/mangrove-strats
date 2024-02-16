// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv-strats/src/strategies/interfaces/IBlast.sol";

contract BaseBlast {
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
}
