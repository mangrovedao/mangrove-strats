// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import {
  MangroveOffer, AbstractRouter, Forwarder
} from "@mgv-strats/src/strategies/offer_forwarder/abstract/Forwarder.sol";
import "@mgv-strats/src/strategies/utils/AccessControlled.sol";

contract StratTest is MangroveTest {
  function $(AccessControlled t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function activateOwnerRouter(IERC20 token, MangroveOffer makerContract, address owner, uint amount) internal {
    AbstractRouter ownerRouter = makerContract.router(owner);
    if (address(ownerRouter).code.length == 0) {
      // in this case, we must be dealing with a Forwarder strat and owner router is not deployed yet.
      // the following call should deploy `ownerRouter` at the correct address.
      Forwarder(payable(makerContract)).ROUTER_FACTORY().deployProxy(owner, makerContract.ROUTER_IMPLEMENTATION());
      assertTrue(address(ownerRouter).code.length > 0, "StratTest: router deployment went wrong");
    }
    vm.startPrank(owner);
    token.approve(address(ownerRouter), amount);
    AbstractRouter(address(ownerRouter)).bind(address(makerContract));
    vm.stopPrank();
  }

  function activateOwnerRouter(IERC20 token, MangroveOffer makerContract, address owner) internal {
    activateOwnerRouter(token, makerContract, owner, type(uint).max);
  }
}
