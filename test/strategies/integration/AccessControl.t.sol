// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import {AccessControlled} from "@mgv-strats/src/strategies/utils/AccessControlled.sol";

contract AccessControlTest is StratTest {
  address payable admin;
  AccessControlled internal testContract;

  function setUp() public virtual override {
    super.setUp();
    admin = freshAddress("admin");

    vm.expectEmit(true, true, true, true);
    emit SetAdmin(admin);
    testContract = new AccessControlled(admin);
  }

  function testCannot_setAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    testContract.setAdmin(freshAddress());
  }

  function test_admin_can_set_admin() public {
    address newAdmin = freshAddress("newAdmin");
    expectFrom($(testContract));
    emit SetAdmin(newAdmin);
    vm.prank(admin);
    testContract.setAdmin(newAdmin);
    assertEq(testContract.admin(), newAdmin, "Incorrect admin");
  }
}
