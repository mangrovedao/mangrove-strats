// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  RenegingForwarder,
  MangroveOffer,
  Tick,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {TransferLib, RL} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {IOrderLogic} from "@mgv-strats/src/strategies/interfaces/IOrderLogic.sol";
import {SmartRouter, AbstractRoutingLogic} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

import {MgvLib, IERC20, OLKey} from "@mgv/src/core/MgvLib.sol";

///@title MangroveOrder. A periphery contract to Mangrove protocol that implements "Good Til Cancel" orders, "Good Til Cancel Enforced" orders, "Post Only" orders, "Immediate Or Cancel" orders, and "Fill Or Kill" orders,
///@notice A GTC order is a buy (sell) limit order complemented by a bid (ask) limit order, called a resting order, that occurs when the buy (sell) order was partially filled.
/// If the GTC is for some amount $a_goal$ at a price $p$, and the corresponding limit order was partially filled for $a_now < a_goal$,
/// the resting order should be posted for an amount $a_later = a_goal - a_now$ at price $p$.
/// If the resting order fails to be posted, the transaction wont fail.
///@notice A GTCE order mimics a GTC order, but shall the resting order fail to be posted, the transaction will revert.
///@notice A PO order is a buy (sell) limit order that is only posted and is not ran against the market.
///@notice An IOC order is a buy (sell) limit order that is ran against the market for a partial or complete fill and no resting order will be posted.
///@notice A FOK order is simply a buy or sell limit order that is either completely filled or cancelled. No resting order is posted.
contract MangroveOrder is RenegingForwarder, IOrderLogic {
  ///@notice MangroveOrder is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param deployer The address of the admin of `this` at the end of deployment
  constructor(IMangrove mgv, RouterProxyFactory factory, address deployer)
    RenegingForwarder(mgv, factory, new SmartRouter())
  {
    _setAdmin(deployer);
  }

  ///@notice compares a taker order with a market order result and checks whether the order was entirely filled
  ///@param tko the taker order
  ///@param res the market order result
  ///@return true if the order was entirely filled, false otherwise.
  function checkCompleteness(TakerOrder calldata tko, TakerOrderResult memory res) internal pure returns (bool) {
    // The order can be incomplete if the price becomes too high or the end of the book is reached.
    if (tko.fillWants) {
      // when fillWants is true, the market order stops when `fillVolume` units of `outbound_tkn` have been obtained (minus potential fees);
      return res.takerGot + res.fee >= tko.fillVolume;
    } else {
      // otherwise, the market order stops when `fillVolume` units of `tko.olKey.inbound_tkn` have been sold.
      return res.takerGave >= tko.fillVolume;
    }
  }

  ///@inheritdoc IOrderLogic
  function take(TakerOrder calldata tko) external payable returns (TakerOrderResult memory res) {
    // Checking whether order is expired
    require(tko.expiryDate == 0 || block.timestamp < tko.expiryDate, "mgvOrder/expired");

    // Notations:
    // NAT_USER: initial value of `msg.sender.balance` (native balance of user)
    // OUT/IN_USER: initial value of `tko.[out|in]bound_tkn.balanceOf(reserve(msg.sender))` (user's reserve balance of tokens with the given logic)
    // NAT_THIS: initial value of `address(this).balance` (native balance of `this`)
    // OUT/IN_THIS: initial value of `tko.[out|in]bound_tkn.balanceOf(address(this))` (`this` balance of tokens)

    (RouterProxy proxy,) = ROUTER_FACTORY.instantiate(msg.sender, ROUTER_IMPLEMENTATION);
    SmartRouter userRouter = SmartRouter(address(proxy));

    bool isComplete;

    logOrderData(tko);

    // this will check if this isn't a post only offer for the market order
    if (tko.orderType.executesMarketOrder()) {
      // State before market order:
      // * User balances: (NAT_USER -`msg.value`, OUT_USER, IN_USER)
      // * `this` balances: (NAT_THIS +`msg.value`, OUT_THIS, IN_THIS)
      (res, isComplete) = executeMarketOrder(tko, userRouter);
      // State after market order:
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)

      // NB: for post only orders, we will keep the same semantic for the state of balances
      // However in the case of post only, since `res.bounty` == `res.takerGot` == `res.takerGave` == 0,
      // the state of balances can be annotated the same as before the market order.
    }

    ///@dev collected bounty compensates gas consumption for the failed offer, but could be lower than the cost of an additional native token transfer
    /// instead of sending the bounty back to `msg.sender` we recycle it into the resting order's provision (so `msg.sender` can retrieve it when deprovisioning).
    /// corner case: if the bounty is large enough, this will make posting of the resting order fail because of `gasprice` overflow.
    /// The funds would then be sent back to `msg.sender` (see below).
    uint fund = msg.value + res.bounty;

    if ( // resting order is:
      tko.orderType.postRestingOrder(isComplete) // required
    ) {
      // When posting a resting order `msg.sender` becomes a maker.
      // For maker orders, outbound tokens are what makers send. Here `msg.sender` sends `tko.olKey.inbound_tkn`.
      // The offer list on which this contract must post `msg.sender`'s resting order is thus `(tko.olKey)`
      // the call below will fill the memory data `res`.
      fund = postRestingOrder({tko: tko, olKey: tko.olKey.flipped(), res: res, userRouter: userRouter, fund: fund});
      // POST (case `postRestingOrder` succeeded):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS, OUT_THIS, IN_THIS)
      // * `fund == 0`
      // * `ownerData[tko.olKey.flipped().hash()][res.offerId].owner == msg.sender`.
      // * Mangrove emitted an `OfferWrite` log whose `maker` field is `address(this)` and `offerId` is `res.offerId`.

      // POST (case `postRestingOrder` failed):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)
      // * `fund == msg.value + res.bounty`.
      // * `res.offerId == 0`
    }

    if (fund > 0) {
      // NB this calls gives reentrancy power to callee, but OK since:
      // 1. callee is `msg.sender` so no griefing risk of making this call fail for out of gas
      // 2. w.r.t reentrancy for profit:
      // * from POST above a reentrant call would entail either:
      //   - `fund == 0` (no additional funds transferred)
      //   - or `fund == msg.value + res.bounty` with `msg.value` being from reentrant call and `res.bounty` from a second resting order.
      // Thus no additional fund can be redeemed by caller using reentrancy.
      (bool noRevert,) = msg.sender.call{value: fund}("");
      require(noRevert, "mgvOrder/refundFail");
    }
    // POST (case `postRestingOrder` succeeded)
    // * (NAT_USER, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS, OUT_THIS, IN_THIS)
    // POST (else)
    // * (NAT_USER+`res.bounty`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS, OUT_THIS, IN_THIS)
    emit MangroveOrderComplete();
    return res;
  }

  ///@notice logs `MangroveOrderStart`
  ///@param tko the arguments in memory of the taker order
  ///@dev this function avoids loading too many variables on the stack
  function logOrderData(TakerOrder memory tko) internal {
    emit MangroveOrderStart({
      olKeyHash: tko.olKey.hash(),
      taker: msg.sender,
      tick: tko.tick,
      orderType: tko.orderType,
      fillVolume: tko.fillVolume,
      fillWants: tko.fillWants,
      offerId: tko.offerId,
      takerGivesLogic: tko.takerGivesLogic,
      takerWantsLogic: tko.takerWantsLogic
    });
  }

  /// @notice Executes a market order on Mangrove according to the taker order.
  /// @param tko arguments in memory of the taker order
  /// @param userRouter the user router
  /// @return res the result of the market order
  /// @return isComplete true if the order was entirely filled, false otherwise.
  function executeMarketOrder(TakerOrder calldata tko, SmartRouter userRouter)
    internal
    returns (TakerOrderResult memory res, bool isComplete)
  {
    // `pullAmount` is derived in `execute` of core protocol to ensure same behavior.
    uint pullAmount = tko.fillWants ? tko.tick.inboundFromOutboundUp(tko.fillVolume) : tko.fillVolume;
    // Pulling funds from `msg.sender`'s routing policy
    RL.RoutingOrder memory inboundRoute = RL.createOrder({fundOwner: msg.sender, token: IERC20(tko.olKey.inbound_tkn)});
    if (address(tko.takerGivesLogic) != address(0)) {
      userRouter.setLogic(inboundRoute, tko.takerGivesLogic);
    }
    require(userRouter.pull(inboundRoute, pullAmount, true) == pullAmount, "mgvOrder/transferInFail");

    // Executes a market order on Mangrove
    (res.takerGot, res.takerGave, res.bounty, res.fee) =
      MGV.marketOrderByTick({olKey: tko.olKey, maxTick: tko.tick, fillVolume: tko.fillVolume, fillWants: tko.fillWants});

    // Current state:
    // * (NAT_USER-`msg.value`, OUT_USER, IN_USER-`takerGives`)
    // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS+`res.takerGot`, IN_THIS+`takerGives`-`res.takerGave`)

    // Checking whether order was entirely filled
    isComplete = checkCompleteness(tko, res);

    // we check whether the order was entirely filled before posting the resting order
    // if the order is a FoK and was not entirely filled, we revert.
    // if the order is partially filled and is to be posted or is an IOC, the market order succeeds.
    // in all cases, if the market order is filled, we do not revert (Here we assume no PO orders are passed to this function)
    require(tko.orderType.marketOrderSucceded(isComplete), "mgvOrder/partialFill");

    RL.RoutingOrder memory outboundRoute;
    if (res.takerGot > 0) {
      // routing outbound token (received by taker) according to takerWantsLogic
      // We approve the user router to pull `takerGot` outbound tokens from this contract.
      TransferLib.approveToken(IERC20(tko.olKey.outbound_tkn), address(userRouter), res.takerGot);
      // pushing tokens received during market order
      outboundRoute = RL.createOrder({token: IERC20(tko.olKey.outbound_tkn), fundOwner: msg.sender});
      if (address(tko.takerWantsLogic) != address(0)) {
        userRouter.setLogic(outboundRoute, tko.takerWantsLogic);
      }
      require(userRouter.push(outboundRoute, res.takerGot) == res.takerGot, "mgvOrder/pushFailed");
    }
    // we now deal with inbound left in case the order was partially filled
    uint inboundLeft = pullAmount - res.takerGave;
    if (inboundLeft > 0) {
      TransferLib.approveToken(IERC20(tko.olKey.inbound_tkn), address(userRouter), inboundLeft);
      // Here we can use `inboundRoute`.
      require(userRouter.push(inboundRoute, inboundLeft) == inboundLeft, "mgvOrder/pushFailed");
    }
    // set back both logic to 0 to save gas if needed
    if (address(tko.takerGivesLogic) != address(0)) {
      userRouter.setLogic(inboundRoute, AbstractRoutingLogic(address(0)));
    }
    // here we check first if the outbound route is initialized
    // In some case, we can have a takerWantsLogic different from 0 that has not been set
    // This is the case if the market order has not been filled at all (i.e. `res.takerGot == 0`)
    if (outboundRoute.token != IERC20(address(0)) && address(tko.takerWantsLogic) != address(0)) {
      userRouter.setLogic(outboundRoute, AbstractRoutingLogic(address(0)));
    }
  }

  ///@notice posts a maker order on the (`olKey`) offer list.
  ///@param tko the arguments in memory of the taker order
  ///@param olKey the offer list key.
  ///@param fund amount of WEIs used to cover for the offer bounty (covered gasprice is derived from `fund`).
  ///@param userRouter the user router
  ///@param res the result of the taker order.
  ///@return refund the amount to refund to the taker of the fund.
  ///@dev if relative limit price of taker order is `ratio` in the (outbound_tkn, inbound_tkn) offer list (represented by `tick=log_{1.0001}(ratio)` )
  ///@dev then entailed relative price for resting order must be `1/ratio` (relative price on the (inbound_tkn, outbound_tkn) offer list)
  ///@dev so with ticks that is `-log(ratio)`, or -tick.
  ///@dev the price of the resting order should be the same as for the max price for the market order.
  function postRestingOrder(
    TakerOrder calldata tko,
    OLKey memory olKey,
    TakerOrderResult memory res,
    SmartRouter userRouter,
    uint fund
  ) internal returns (uint refund) {
    // computing hash in advance
    bytes32 olKeyHash = olKey.hash();

    // computing residual values
    Tick residualTick = Tick.wrap(-Tick.unwrap(tko.tick));
    uint residualGives;
    if (tko.fillWants) {
      // partialFill => tko.fillVolume > res.takerGot + res.fee
      uint residualWants = tko.fillVolume - (res.takerGot + res.fee);
      // adapting residualGives to match relative limit price chosen by the taker
      residualGives = residualTick.outboundFromInboundUp(residualWants);
    } else {
      // partialFill => tko.fillVolume > res.takerGave
      residualGives = tko.fillVolume - res.takerGave;
    }
    OfferArgs memory args = OfferArgs({
      olKey: olKey,
      tick: residualTick,
      gives: residualGives,
      gasreq: tko.restingOrderGasreq,
      gasprice: 0, // ignored
      fund: fund,
      noRevert: true // returns 0 when MGV reverts
    });
    if (tko.offerId == 0) {
      // posting a new offer
      (res.offerId, res.offerWriteData) = _newOffer(args, msg.sender);
    } else {
      // updating an existing offer
      uint offerId = tko.offerId;
      // chekcing ownership of offer since we use internal version of `updateOffer` which is unguarded
      require(ownerData[olKeyHash][offerId].owner == msg.sender, "AccessControlled/Invalid");
      // msg sender might have given an offerId that is already live
      // we disallow this to avoid confusion
      require(!MGV.offers(olKey, offerId).isLive(), "mgvOrder/offerAlreadyActive");
      bytes32 repostData = _updateOffer(args, offerId);
      res.offerWriteData = repostData;
      if (repostData == REPOST_SUCCESS) {
        res.offerId = offerId;
      } else {
        res.offerId = 0;
      }
    }
    if (res.offerId == 0) {
      // either:
      // - residualGives is below current density
      // - `fund` is too low and would yield a gasprice that is lower than Mangrove's
      // - `fund` is too high and would yield a gasprice overflow
      // - offer list is not active (Mangrove is not dead otherwise market order would have reverted)
      // So the resting order was not posted.
      // in this case, if we have a GTFE order, we revert.
      // If this is a PO order, we could proceed, but we revert to avoid further gas loss.
      require(!tko.orderType.enforcePostRestingOrder(), "mgvOrder/RestingOrderFailed");
      // `fund` is no longer needed so sending it back to `msg.sender`
      refund = fund;
    } else {
      // offer was successfully posted
      // `fund` was used and we leave `refund` at 0.

      // update or create routes for the given offer if needed
      RL.RoutingOrder memory route = RL.RoutingOrder({
        token: IERC20(tko.olKey.outbound_tkn),
        fundOwner: msg.sender,
        olKeyHash: olKeyHash,
        offerId: res.offerId
      });
      if (address(tko.takerGivesLogic) != address(0)) {
        // because the taker becomes the maker, the outbound token logic is the takerGivesLogic
        userRouter.setLogic(route, tko.takerGivesLogic);
      }
      route.token = IERC20(tko.olKey.inbound_tkn);
      if (address(tko.takerWantsLogic) != address(0)) {
        // because the taker becomes the maker, the inbound token logic is the takerWantsLogic
        userRouter.setLogic(route, tko.takerWantsLogic);
      }

      // setting expiry date for the resting order
      if (tko.expiryDate > 0) {
        _setReneging(olKeyHash, res.offerId, tko.expiryDate, 0);
      }
    }
  }
}
