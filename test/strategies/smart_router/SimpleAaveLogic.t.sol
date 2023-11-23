// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MgvOrder_Test} from "../MgvOrder.t.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/aave/v3/IPool.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
// import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";

abstract contract SimpleAaveLogic_Test is MgvOrder_Test {
  IPool public aave;

  function overlyingOf(address _token) internal view returns (address) {
    return aave.getReserveData(_token).aTokenAddress;
  }

  function hasMarket(address _token) internal view returns (bool) {
    return overlyingOf(_token) != address(0);
  }

  function _supply(address _token, uint _amount, address _onBehalf) internal {
    TransferLib.approveToken(IERC20(_token), $(aave), _amount);
    aave.supply(_token, _amount, _onBehalf, 0);
  }

  function dealATokens(address _to, address _token, uint _amount) internal {
    deal(_token, $(this), _amount);
    _supply(_token, _amount, _to);
  }

  function aTokenBalanceOf(address _token, address _user) internal view returns (uint) {
    return IERC20(overlyingOf(_token)).balanceOf(_user);
  }

  function setUp() public virtual override {
    aave = IPoolAddressesProvider(fork.get("AaveAddressProvider")).getPool();
    super.setUp();
  }
}

contract AaveLogicInbOutb_Test is SimpleAaveLogic_Test {}
