// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {
  Forwarder,
  IMangrove,
  IERC20,
  RouterProxyFactory
} from "@mgv-strats/src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ITesterContract, ILiquidityProvider} from "./ITesterContract.sol";
import {SimpleRouter, AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/SimpleRouter.sol";
import {MgvLib, OLKey, Tick, TickLib} from "@mgv/src/core/MgvLib.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

contract ForwarderTester is ITesterContract, Forwarder {
  constructor(IMangrove mgv, AbstractRouter routerImplementation)
    Forwarder(mgv, new RouterProxyFactory(), routerImplementation)
  {}

  /// @inheritdoc ILiquidityProvider
  function newOffer(OLKey memory olKey, Tick tick, uint gives, uint gasreq)
    public
    payable
    override
    returns (uint offerId)
  {
    (offerId,) = _newOffer(
      OfferArgs({
        olKey: olKey,
        tick: tick,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        fund: msg.value,
        noRevert: false // propagates Mangrove's revert data in case of newOffer failure
      }),
      msg.sender
    );
  }

  ///@inheritdoc ILiquidityProvider
  ///@dev the `gasprice` argument is always ignored in `Forwarder` logic, since it has to be derived from `msg.value` of the call (see `_newOffer`).
  function updateOffer(OLKey memory olKey, Tick tick, uint gives, uint offerId, uint gasreq)
    public
    payable
    override
    onlyOwner(olKey.hash(), offerId)
  {
    OfferArgs memory args;

    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    // it might be tempting to include `od.weiBalance` here but this will trigger a recomputation of the `gasprice`
    // each time a offer is updated.
    args.fund = msg.value; // if inside a hook (Mangrove is `msg.sender`) this will be 0
    args.olKey = olKey;
    args.tick = tick;
    args.gives = gives;
    args.gasreq = gasreq;
    args.noRevert = false; // will throw if Mangrove reverts
    // weiBalance is used to provision offer
    _updateOffer(args, offerId);
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision)
    public
    mgvOrOwner(olKey.hash(), offerId)
    returns (uint freeWei)
  {
    (freeWei,) = _retractOffer(olKey, offerId, false, deprovision);
    (bool noRevert,) = ownerOf(olKey.hash(), offerId).call{value: freeWei}("");
    require(noRevert, "mgvOffer/weiTransferFail");
  }

  ///@inheritdoc ITesterContract
  function tokenBalance(IERC20 token, address owner) external view override returns (uint) {
    return router(owner).tokenBalanceOf(RL.createOrder({token: token, fundOwner: owner}));
  }

  ///@inheritdoc ITesterContract
  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq)
    external
    payable
    returns (uint offerId)
  {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    return newOffer(olKey, tick, gives, gasreq);
  }

  ///@inheritdoc ITesterContract
  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint offerId, uint gasreq) external payable {
    Tick tick = TickLib.tickFromVolumes(wants, gives);
    updateOffer(olKey, tick, gives, offerId, gasreq);
  }
}
