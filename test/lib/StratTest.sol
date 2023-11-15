// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import {MangroveOffer, RouterProxy, AbstractRouter} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import "@mgv-strats/src/strategies/utils/AccessControlled.sol";

contract StratTest is MangroveTest {
  function $(AccessControlled t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function activateOwnerRouter(IERC20 token, MangroveOffer makerContract, address owner) internal {
    (RouterProxy ownerProxy,) = makerContract.ROUTER_FACTORY().instantiate(owner, makerContract.ROUTER_IMPLEMENTATION());
    vm.startPrank(owner);
    token.approve(address(ownerProxy), type(uint).max);
    AbstractRouter(address(ownerProxy)).bind(address(makerContract));
    vm.stopPrank();
  }
}
