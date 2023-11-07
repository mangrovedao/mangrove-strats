// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import {
  SmartRouterProxyFactory,
  SmartRouter,
  SmartRouterProxy
} from "@mgv-strats/src/strategies/routers/SmartRouterProxyFactory.sol";

contract SmartRouterProxyFactoryTest is StratTest, SmartRouterProxyFactory {
  SmartRouter router = SmartRouter(freshAddress());
  address owner = freshAddress();

  function test_computeProxyAddress() public {
    address proxy = computeProxyAddress(router, owner, address(this));
    SmartRouterProxy proxy_ = deploy(router, owner);
    assertEq(proxy, address(proxy_), "Computed address is incorrect");
  }

  event SetAdmin(address);

  function test_deployIfNeeded() public {
    address proxy = computeProxyAddress(router, owner, address(this));
    expectFrom(address(proxy));
    emit SetAdmin(owner);
    (, bool created) = deployIfNeeded(router, owner);
    assertTrue(created, "Proxy was not created");
    (, created) = deployIfNeeded(router, owner);
    assertTrue(!created, "Proxy should not be deployed again");
  }
}
