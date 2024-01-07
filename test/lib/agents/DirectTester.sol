// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Direct, IERC20} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {ITesterContract, ILiquidityProvider} from "./ITesterContract.sol";

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {MgvLib, OLKey, Tick, TickLib} from "@mgv/src/core/MgvLib.sol";

contract DirectTester is Direct, ITesterContract {
  bytes32 constant retData = "lastLook/testData";

  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, RouterParams memory routerParams) Direct(mgv, routerParams) {}

  function __lastLook__(MgvLib.SingleOrder calldata) internal virtual override returns (bytes32) {
    return retData;
  }

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

  ///@inheritdoc ITesterContract
  function tokenBalance(IERC20 token, address) external view returns (uint) {
    return _isRouting() ? router().tokenBalanceOf(RL.createOrder(token, FUND_OWNER)) : token.balanceOf(FUND_OWNER);
  }
}
