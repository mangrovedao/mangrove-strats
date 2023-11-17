// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {ExpirableForwarder, MangroveOffer} from "@mgv-strats/src/strategies/offer_forwarder/ExpirableForwarder.sol";
import {
  TransferLib,
  RouterProxyFactory,
  AbstractRouter,
  RouterProxy,
  RL
} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";

///@title MangroveAmplifier. A periphery contract to Mangrove protocol that implements "liquidity amplification". It allows offer owner to post offers on multiple markets with the same collateral.
/// e.g an amplified offer is of the form:`ampOffer = {makerGives: 1000 USDT, makerWants:(1001 DAI, 0.03 WBTC, 0.5 WETH)` where any trade for `(takerWants:USDT, takerGives:DAI|WBTC|WETH)`
/// must end up in the following state (suppose `takerGives: n DAI` and `takerWants: k USDT`):
/// `ampOffer = {makerGives: 1000 - k USDT, makerWants:(1001 - n DAI, (1000 - k) * 0.03/1000 WBTC, (1000 - k)* 0.5/1000 WETH )}` if none of the makerWants field are rounded down to 0
/// If any of the `makerWants` field becomes 0, the corresponding offer should be retracted.

contract MangroveAmplifier is ExpirableForwarder {
  ///@notice offer bundle identifier
  uint private __bundleId;

  ///@notice maps a `bundleId` to the set of inbound_tokens of the bundle
  mapping(uint bundleId => IERC20[] inbound_tkns) private __inboundTknsOfBundleId;

  ///@notice maps a `bundleId` to the set of pairs (tickSpacing, offerId) of the bundle
  mapping(uint bundleId => uint[2][] ticks_offerIds) private __ticks_offerIdsOfBundleId;

  ///@notice maps an offer list key hash and an offerId to the bundle in which this offer is.
  ///@dev given an incoming taker order  `(offerId, olKey)` one may retrieve all offers that are in the same bundle doing:
  /// 1. ` bundleId = __bundleIdOfOfferId[olKey.hash][offerId]`
  /// 2. `[tick_j, offerId_j] = __ticks_offerIdsOfBundleId[bundleId][j]`
  /// 3. `inbound_j` = __inboundTknsOfBundleId[bundleId][j]`
  /// for all j <= `__ticks_offerIdsOfBundleId[bundleId].length`
  mapping(bytes32 olKeyHash => mapping(uint => uint)) private __bundleIdOfOfferId;

  ///@notice MangroveAmplifier is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param deployer The address of the admin of `this` at the end of deployment
  constructor(IMangrove mgv, RouterProxyFactory factory, address deployer)
    ExpirableForwarder(mgv, factory, new SmartRouter())
  {
    _setAdmin(deployer);
  }

  struct HeapVarsNewBundle {
    uint[2][] ticks_offerIds;
    uint availableProvision;
    uint provision;
    uint offerId;
    OLKey olKey;
  }

  ///@notice posts bundle of offers on Mangrove so as to amplify outbound token
  ///@param outbound_tkn the promised asset for all offers of the bundle
  ///@param outVolume how much assets each offer promise
  ///@param inboundTkns an array of length `n` such that `inboundTkns[i]` is the inbound of the i^th offer of the bundle
  ///@param params the offers parameters such that `params[i]=[inVolume, gasreq, provision, tick]` where:
  /// * `inVolume` is the amount of inbound token the i^th offer of the bundle wants
  /// * `gasreq` is the gas required by the i^th offer (gas may differ between offer because of different routing strategies)
  /// * `provision` is the portion of `msg.value` that should be allocated to the provision of the i^th offer
  /// * `tick` is the tick spacing parameter that charaterizes the offer list to which the offer should be posted.
  ///@return freshBundleId the bundle identifier
  function newBundle(
    IERC20 outbound_tkn,
    uint outVolume,
    IERC20[] calldata inboundTkns, // `OlKeys[i].outbound_tkn` must be the same for all `i`
    uint[4][] calldata params // params[0]: inVolume, params[1] = gasreq, params[2] = provision, params[3] = tick
  ) public payable returns (uint freshBundleId) {
    HeapVarsNewBundle memory vars;
    freshBundleId = __bundleId++;
    vars.ticks_offerIds = new uint[2][](params.length);
    vars.availableProvision = msg.value;
    for (uint i; i < params.length; i++) {
      require(params[2][i] <= vars.availableProvision, "MgvAmplifier/NotEnoughProvisions");
      // making sure no native token remains in the strat
      // note if `vars.provision` is insufficient to cover `gasreq=params[2][i]` the call below will revert
      vars.provision = i == params.length - 1 ? vars.availableProvision : params[2][i];
      vars.olKey =
        OLKey({outbound_tkn: address(outbound_tkn), inbound_tkn: address(inboundTkns[i]), tickSpacing: params[3][i]});
      (vars.offerId,) = _newOffer(
        OfferArgs({
          olKey: vars.olKey,
          tick: TickLib.tickFromVolumes(params[0][i], outVolume),
          gives: outVolume,
          gasreq: params[1][i],
          gasprice: 0, // ignored in Forwarder strats
          fund: vars.provision,
          noRevert: false // revert if unable to post
        }),
        msg.sender
      );
      vars.availableProvision -= params[2][i];
      vars.ticks_offerIds[i] = [params[3][i], vars.offerId];
      __bundleIdOfOfferId[vars.olKey.hash()][vars.offerId] = freshBundleId;
    }
    __ticks_offerIdsOfBundleId[freshBundleId] = vars.ticks_offerIds;
    __inboundTknsOfBundleId[freshBundleId] = inboundTkns;
  }

  ///@notice updates a bundle of offer after one of them has be partially filled.
  ///@param outbound_tkn the outbound token of the bundle
  ///@param offerId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param ticks_offerIds the array of elements `[tick_i, offerId_i]` where `tick_i` is the tick spacing of the offer list in which `offerId_i` lives.
  ///@param inbound_tkns the array of inbound tokens of each member of the bundle to update
  ///@param outboundVolume the new volume that each offer of the bundle should now offer
  function _updateBundle(
    IERC20 outbound_tkn,
    uint offerId,
    uint[2][] memory ticks_offerIds,
    IERC20[] memory inbound_tkns,
    uint outboundVolume
  ) internal {
    // updating outbound volume for all offers of the bundle --except the one that is being executed since the offer list is locked
    for (uint i; i < ticks_offerIds.length; i++) {
      if (ticks_offerIds[1][i] != offerId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(inbound_tkns[i]),
          tickSpacing: ticks_offerIds[0][i]
        });
        Offer offer_i = MGV.offers(olKey_i, ticks_offerIds[1][i]);
        OfferDetail offerDetail_i = MGV.offerDetails(olKey_i, ticks_offerIds[1][i]);
        // Updating offer_i
        OfferArgs memory args;
        args.olKey = olKey_i;
        args.tick = offer_i.tick(); // same price
        args.gives = outboundVolume; // new volume
        args.gasreq = offerDetail_i.gasreq();
        args.noRevert = true;
        // call below will retract the offer without reverting if update fails (for instance if the density it too low)
        _updateOffer(args, ticks_offerIds[1][i]);
      }
    }
  }

  ///@notice retracts a bundle of offers
  ///@param outbound_tkn the outbound token of the bundle
  ///@param offerId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param ticks_offerIds the array of elements `[tick_i, offerId_i]` where `tick_i` is the tick spacing of the offer list in which `offerId_i` lives.
  ///@param inbound_tkns the array of inbound tokens of each member of the bundle to retract
  ///@param deprovision whether retracting the offer should also deprovision offers on Mangrove
  ///@return freeWei the amount of native tokens on this contract's balance that should be sent to msg.sender
  function _retractBundle(
    IERC20 outbound_tkn,
    uint offerId,
    uint[2][] memory ticks_offerIds,
    IERC20[] memory inbound_tkns,
    bool deprovision
  ) internal returns (uint freeWei) {
    for (uint i; i < ticks_offerIds.length; i++) {
      if (ticks_offerIds[1][i] != offerId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(inbound_tkns[i]),
          tickSpacing: ticks_offerIds[0][i]
        });
        freeWei += _retractOffer(olKey_i, ticks_offerIds[1][i], deprovision);
      }
    }
  }

  ///@inheritdoc MangroveOffer
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint) {
    // this will use offer owner's router to pull `amount` to this contract
    uint missing = super.__get__(amount, order);

    // we know take care of updating the other offers that are part of the same bundle
    uint bundleId = __bundleIdOfOfferId[order.olKey.hash()][order.offerId];
    uint[2][] memory ticks_offerIds = __ticks_offerIdsOfBundleId[bundleId];
    IERC20[] memory inbound_tkns = __inboundTknsOfBundleId[bundleId];
    // if funds are missing, the trade will fail and one should retract the bundle
    // otherwise we update the bundle to the new volume
    if (missing == 0) {
      _updateBundle(
        IERC20(order.olKey.outbound_tkn),
        order.offerId,
        ticks_offerIds,
        inbound_tkns,
        order.offer.gives() - order.takerWants
      );
    } else {
      // not deprovisionning to save execution gas
      _retractBundle(IERC20(order.olKey.outbound_tkn), order.offerId, ticks_offerIds, inbound_tkns, false);
    }
    return missing;
  }
}
