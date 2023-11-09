// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import {
  SmartRouterProxyFactory,
  SmartRouter,
  SmartRouterProxy
} from "@mgv-strats/src/strategies/routers/SmartRouterProxyFactory.sol";

contract SmartRouterProxyFactoryTest is StratTest {
  SmartRouterProxyFactory private proxyFactory;
  address private owner;

  function setUp() public virtual override {
    proxyFactory = new SmartRouterProxyFactory(new SmartRouter());
    owner = freshAddress("Owner");
  }

  function test_computeProxyAddress() public {
    address proxy = proxyFactory.computeProxyAddress(owner);
    SmartRouter proxy_ = proxyFactory.deploy(owner);
    assertEq(proxy, address(proxy_), "Computed address is incorrect");
  }

  event SetAdmin(address);

  function test_deployIfNeeded() public {
    address proxy = proxyFactory.computeProxyAddress(owner);
    expectFrom(address(proxy));
    emit SetAdmin(owner);
    (, bool created) = proxyFactory.deployIfNeeded(owner);
    assertTrue(created, "Proxy was not created");
    (, created) = proxyFactory.deployIfNeeded(owner);
    assertTrue(!created, "Proxy should not be deployed again");
  }
}
