// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {BaseMangroveOrder} from "./BaseMangroveOrder.sol";
import {SimpleRouter} from "./routers/SimpleRouter.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title MangroveOrder. A periphery contract to Mangrove protocol that implements "Good till cancelled" (GTC) orders as well as "Fill or kill" (FOK) orders.
contract MangroveOrder is BaseMangroveOrder {
  constructor(IMangrove mgv, address deployer, uint gasreq)
    BaseMangroveOrder(mgv, new SimpleRouter(), deployer, gasreq)
  {}
}
