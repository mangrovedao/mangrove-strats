// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {StratTest} from "@mgv-strats/test/lib/StratTest.sol";
import {RouterProxyFactory, RouterProxy} from "@mgv-strats/src/strategies/routers/RouterProxyFactory.sol";
import {AbstractRouter, SimpleRouter} from "@mgv-strats/src/strategies/routers/SimpleRouter.sol";

contract RouterProxyFactoryTest is StratTest {
  RouterProxyFactory private proxyFactory;
  AbstractRouter private routerImpl;
  address private owner;

  function setUp() public virtual override {
    proxyFactory = new RouterProxyFactory();
    owner = freshAddress("Owner");
    routerImpl = new SimpleRouter();
  }

  function test_computeProxyAddress() public {
    RouterProxy proxy = RouterProxy(proxyFactory.computeProxyAddress(owner, routerImpl));
    RouterProxy proxy_ = proxyFactory.deployProxy(owner, routerImpl);
    assertEq(address(proxy), address(proxy_), "Computed address is incorrect");
  }

  function test_instantiate() public {
    RouterProxy proxy = RouterProxy(proxyFactory.computeProxyAddress(owner, routerImpl));
    expectFrom(address(proxy));
    emit SetAdmin(owner);
    (, bool created) = proxyFactory.instantiate(owner, routerImpl);
    assertTrue(created, "Proxy was not created");
    (, created) = proxyFactory.instantiate(owner, routerImpl);
    assertTrue(!created, "Proxy should not be deployed again");
  }

  function test_deploysSetsAdmin() public {
    RouterProxy proxy = proxyFactory.deployProxy(owner, routerImpl);
    assertEq(AbstractRouter(address(proxy)).admin(), owner, "Incorrect admin");
  }
}
