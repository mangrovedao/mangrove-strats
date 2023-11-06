// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "@mgv/test/lib/MangroveTest.sol";
import {SmartRouterProxy} from "@mgv-strats/src/strategies/routers/SmartRouterProxy.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {console} from "@mgv/lib/Debug.sol";

contract DeploySmartRouterProxy is MangroveTest {
  function test_gasreq_deploy_smart_router_proxy() public {
    address owner = $(this);

    SmartRouter impl = SmartRouter(address(0));

    uint gas = gasleft();
    SmartRouterProxy proxy = new SmartRouterProxy{salt:bytes32("")}(impl);
    gas = gas - gasleft();

    console.log("gas used: %d", gas);
  }
}
