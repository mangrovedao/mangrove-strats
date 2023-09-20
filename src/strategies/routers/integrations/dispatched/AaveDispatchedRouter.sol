// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {MonoRouter, AbstractRouter} from "../../abstract/MonoRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer} from "../AaveMemoizer.sol";
import {ReserveConfiguration, DataTypes} from "../../abstract/AbstractAaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/// @title `AaveDispatchedRouter` is a router contract for Aave used by the `Dispatcher` contract.
contract AaveDispatchedRouter is MonoRouter, AaveMemoizer {
  constructor(uint routerGasreq_, address addressesProvider, uint interestRateMode)
    MonoRouter(routerGasreq_)
    AaveMemoizer(addressesProvider, interestRateMode)
  {}

  function __checkList__(IERC20 token, address reserveId) internal view override {
    require(token.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
    Memoizer memory m;
    IERC20 overlying = overlying(token, m);
    require(overlying.allowance(reserveId, address(this)) > 0, "AaveDispatchedRouter/NotApproved");
  }

  function __pull__(IERC20 token, address reserveId, uint amount, bool strict) internal virtual override returns (uint) {
    Memoizer memory m;
    IERC20 overlying = overlying(token, m);
    require(overlying.balanceOf(reserveId) >= amount, "AaveDispatchedRouter/NotEnoughBalance");
    require(overlying.allowance(reserveId, address(this)) >= amount, "AaveDispatchedRouter/NotApproved");
    overlying.transferFrom(reserveId, address(this), amount);
  }

  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint pushed) {}

  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {}
}
