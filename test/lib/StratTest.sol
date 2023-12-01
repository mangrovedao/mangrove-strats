// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import {
  MangroveOffer, AbstractRouter, Forwarder
} from "@mgv-strats/src/strategies/offer_forwarder/abstract/Forwarder.sol";
import "@mgv-strats/src/strategies/utils/AccessControlled.sol";

contract StratTest is MangroveTest {
  // for RenegingForwarder
  event SetReneging(bytes32 indexed olKeyHash, uint indexed offerId, uint date, uint volume);
  // all strats
  event LogIncident(bytes32 indexed olKeyHash, uint indexed offerId, bytes32 makerData, bytes32 mgvData);
  event Transfer(address indexed from, address indexed to, uint value);
  event SetAdmin(address);

  // all routers
  event MakerBind(address indexed maker);
  event MakerUnbind(address indexed maker);

  function $(AccessControlled t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function activateOwnerRouter(IERC20 token, MangroveOffer makerContract, address owner, uint amount)
    internal
    returns (AbstractRouter ownerRouter)
  {
    ownerRouter = makerContract.router(owner);
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

  function activateOwnerRouter(IERC20 token, MangroveOffer makerContract, address owner)
    internal
    returns (AbstractRouter ownerRouter)
  {
    ownerRouter = activateOwnerRouter(token, makerContract, owner, type(uint).max);
  }
}
