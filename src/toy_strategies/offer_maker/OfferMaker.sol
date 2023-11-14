// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {ILiquidityProvider} from "@mgv-strats/src/strategies/interfaces/ILiquidityProvider.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {Tick, TickLib} from "@mgv/lib/core/TickLib.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

contract OfferMaker is ILiquidityProvider, Direct {
  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, RouterParams memory routerParams) Direct(mgv, routerParams) {}

  ///@inheritdoc ILiquidityProvider
  function newOffer(OLKey memory olKey, Tick tick, uint gives, uint gasreq)
    public
    payable
    override
    onlyAdmin
    returns (uint offerId)
  {
    (offerId,) = _newOffer(
      OfferArgs({olKey: olKey, tick: tick, gives: gives, gasreq: gasreq, gasprice: 0, fund: msg.value, noRevert: false})
    );
  }

  ///@inheritdoc ILiquidityProvider
  function updateOffer(OLKey memory olKey, Tick tick, uint gives, uint offerId, uint gasreq)
    public
    payable
    override
    onlyAdmin
  {
    _updateOffer(
      OfferArgs({olKey: olKey, tick: tick, gives: gives, gasreq: gasreq, gasprice: 0, fund: msg.value, noRevert: false}),
      offerId
    );
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision)
    public
    adminOrCaller(address(MGV))
    returns (uint freeWei)
  {
    freeWei = _retractOffer(olKey, offerId, deprovision);
    if (freeWei > 0) {
      require(MGV.withdraw(freeWei), "Direct/withdrawFail");
      // sending native tokens to `msg.sender` prevents reentrancy issues
      // (the context call of `retractOffer` could be coming from `makerExecute` and a different recipient of transfer than `msg.sender` could use this call to make offer fail)
      (bool noRevert,) = admin().call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
  }

  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq)
    external
    payable
    returns (uint offerId)
  {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    return newOffer(olKey, tick, gives, gasreq);
  }

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq) external payable {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    updateOffer(olKey, tick, gives, offerId, gasreq);
  }

  function tokenBalance(IERC20 token, address) external view returns (uint) {
    return _isRouting() ? router().balanceOfReserve(RL.createOrder(token, FUND_OWNER)) : token.balanceOf(FUND_OWNER);
  }
}
