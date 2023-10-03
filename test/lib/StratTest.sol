// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_strat_src/strategies/utils/AccessControlled.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "lib/permit2/test/utils/DeployPermit2.sol";

contract StratTest is MangroveTest, DeployPermit2 {
  IPermit2 public permit2;

  function $(AccessControlled t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function setUp() public virtual override {
    permit2 = IPermit2(deployPermit2());

    super.setUp();
  }
}
