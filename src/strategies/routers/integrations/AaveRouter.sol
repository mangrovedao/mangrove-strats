// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from "../vendor/aave/v3/IPoolAddressesProvider.sol";

import {DispatchedRouter} from "../abstract/DispatchedRouter.sol";
import {AbstractRouter} from "../abstract/AbstractRouter.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

contract AaveRouter is DispatchedRouter {
  struct AaveRouterStorage {}

  constructor(bytes memory storage_key) DispatchedRouter(storage_key) {}

  function __pull__(IERC20 token, address reserveId, uint amount, bool strict) internal virtual override returns (uint) {}

  function __push__(IERC20 token, address reserveId, uint amount) internal virtual override returns (uint pushed) {}

  function __checkList__(IERC20 token, address reserveId) internal view virtual override {}

  function balanceOfReserve(IERC20 token, address reserveId) public view virtual override returns (uint) {}

  function __initialize__(bytes calldata initData) internal virtual override returns (bool) {}

  function maxDeposit(IERC20 token) public view virtual override returns (uint) {}

  function maxWithdraw(IERC20 token) public view virtual override returns (uint) {}

  function previewDeposit(IERC20 token, uint amount) public view virtual override returns (uint) {}

  function previewWithdraw(IERC20 token, uint amount) public view virtual override returns (uint) {}
}
