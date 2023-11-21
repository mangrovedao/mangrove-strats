// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  ExpirableForwarder,
  MangroveOffer,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/offer_forwarder/ExpirableForwarder.sol";
import {TransferLib, AbstractRouter, RL} from "@mgv-strats/src/strategies/MangroveOffer.sol";
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

  struct BundledOffer {
    IERC20 inbound_tkn; // the inbound token of the offer in the bundle
    uint tick; // the tick spacing of the offer list in which the offer is posted
    uint offerId; // the offer of the offer
  }

  ///@notice maps a `bundleId` to a set of bundled offers
  mapping(uint bundleId => BundledOffer[]) __bundles;

  ///@notice maps an offer list key hash and an offerId to the bundle in which this offer is.
  mapping(bytes32 olKeyHash => mapping(uint offerId => uint bundleId)) private __bundleIdOfOfferId;

  ///@notice logs beginning of bundle creation
  ///@param bundleId bundle identifier
  event InitBundle(uint indexed bundleId);

  ///@notice logs end of bundle creation
  ///@dev to know which offer are part of the bundle one needs to track `NewOwnedOffer(olKeyHash, offerId, owner)` emitted in between `InitBundle` and `EndBundle`
  ///@dev the expiry date of the bundle is given by the logs `SetExpiry(olKeyHash, offerId, expiryDate)` of each offer of the bundle (all dates are the same).
  event EndBundle();

  ///@notice MangroveAmplifier is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  ///@param deployer The address of the admin of `this` at the end of deployment
  constructor(IMangrove mgv, RouterProxyFactory factory, address deployer)
    ExpirableForwarder(mgv, factory, new SmartRouter())
  {
    _setAdmin(deployer);
  }

  struct FixedBundleParams {
    IERC20 outbound_tkn; //the promised asset for all offers of the bundle
    uint outVolume; // how much assets each offer promise
    AbstractRouter outboundLogic; // the logic to manage liquidity sourcing.  Use `AbstractRouter(address(0))` for simple routing.
    uint expiryDate; // date of expiration of each offer of the bundle. Use 0 for no expiry.
  }

  struct VariableBundleParams {
    uint inVolume; // the amount of inbound token this offer wants
    uint gasreq; // the gas required by this offer (gas may differ between offer because of different routing strategies)
    uint provision; // the portion of `msg.value` that should be allocated to the provision of this offer
    uint tick; // the tick spacing parameter that charaterizes the offer list to which this offer should be posted.
    AbstractRouter inboundLogic; //the logics to manage liquidity targetting for this offer of the bundle. Use `AbstractRouter(address(0))` for simple routing.
    IERC20 inbound_tkn; // the inbound token this offer expects
  }

  struct HeapVarsNewBundle {
    BundledOffer bundledOffer; // the created bundle
    uint availableProvision; // remaining funds to provision offers of the bundle
    uint provision; // provision allocated for the current offer
    OLKey olKey; // olKey for the current offer
    bytes32 olKeyHash; // hash of the above olKey
    RouterProxy proxy; // address of the offer owner router proxy (to be called when setting routing logics)
    RL.RoutingOrder routingOrder; // routing order to set the logic
  }

  ///@notice posts bundle of offers on Mangrove so as to amplify a certain volume of outbound tokens
  ///@param fx params shared by all offers of the bundle
  ///@param vr array of params for each offer of the bundle
  ///@return freshBundleId the bundle identifier
  function newBundle(FixedBundleParams calldata fx, VariableBundleParams[] calldata vr)
    public
    payable
    returns (uint freshBundleId)
  {
    HeapVarsNewBundle memory vars;
    freshBundleId = __bundleId++;

    emit InitBundle(freshBundleId);

    vars.availableProvision = msg.value;
    for (uint i; i < vr.length; i++) {
      require(vr[i].provision <= vars.availableProvision, "MgvAmplifier/NotEnoughProvisions");
      // making sure no native token remains in the strat
      // note if `vars.provision` is insufficient to cover `gasreq=vr[i].gasreq` the call below will revert
      vars.provision = i == vr.length - 1 ? vars.availableProvision : vr[i].provision;
      vars.olKey = OLKey({
        outbound_tkn: address(fx.outbound_tkn),
        inbound_tkn: address(vr[i].inbound_tkn),
        tickSpacing: vr[i].tick
      });
      // memoizing hash
      vars.olKeyHash = vars.olKey.hash();
      // posting new offer on Mangove
      (vars.bundledOffer.offerId,) = _newOffer(
        OfferArgs({
          olKey: vars.olKey,
          tick: TickLib.tickFromVolumes(vr[i].inVolume, fx.outVolume),
          gives: fx.outVolume,
          gasreq: vr[i].gasreq,
          gasprice: 0, // ignored in Forwarder strats
          fund: vars.provision,
          noRevert: false // revert if unable to post
        }),
        msg.sender
      );

      // Setting logic to push inbound tokens offer
      if (address(vr[i].inboundLogic) != address(0)) {
        (vars.proxy,) = ROUTER_FACTORY.instantiate(msg.sender, ROUTER_IMPLEMENTATION);
        vars.routingOrder.token = vr[i].inbound_tkn;
        vars.routingOrder.olKeyHash = vars.olKeyHash;
        vars.routingOrder.offerId = vars.bundledOffer.offerId;
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder, vr[i].inboundLogic);
      }

      // Setting logic to pull outbount tokens for the same offer
      if (address(fx.outboundLogic) != address(0)) {
        vars.routingOrder.token = fx.outbound_tkn;
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder, fx.outboundLogic);
      }

      // Setting expiry date if required
      if (fx.expiryDate != 0) {
        _setExpiry(vars.olKeyHash, vars.bundledOffer.offerId, fx.expiryDate);
      }

      // Updating remaining available native tokens for provisions
      vars.availableProvision -= vars.provision;

      // pushing to storage the new bundle
      vars.bundledOffer.tick = vr[i].tick;
      vars.bundledOffer.inbound_tkn = vr[i].inbound_tkn;
      __bundleIdOfOfferId[vars.olKeyHash][vars.bundledOffer.offerId] = freshBundleId;
      __bundles[freshBundleId].push(vars.bundledOffer);
    }
    emit EndBundle();
  }

  ///@notice owner of the offer bundle
  ///@param bundle of offers whose owner is queried
  ///@param outbound_tkn of the bundle
  ///@return address of the owner of the bundle
  ///@dev call assume bundle has at least one offer.
  function ownerOf(BundledOffer[] memory bundle, IERC20 outbound_tkn) public view returns (address) {
    OLKey memory olKey = OLKey({
      outbound_tkn: address(outbound_tkn),
      inbound_tkn: address(bundle[0].inbound_tkn),
      tickSpacing: bundle[0].tick
    });
    return (ownerOf(olKey.hash(), bundle[0].offerId));
  }

  ///@notice updates a bundle of offers, possibly during the execution of the logic of one of them.
  ///@param bundle the offer bundle to update
  ///@param outbound_tkn the outbound token of the bundle
  ///@param skipId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param outboundVolume the new volume that each offer of the bundle should now offer
  ///@param updateExpiry whether the update also changes expiry date of the bundle
  ///@param expiryDate the new date (if `updateExpiry` is true) for the expiry of the offers of the bundle. 0 for no expiry
  function _updateBundle(
    BundledOffer[] memory bundle,
    IERC20 outbound_tkn,
    uint skipId,
    uint outboundVolume,
    bool updateExpiry,
    uint expiryDate
  ) internal {
    // updating outbound volume for all offers of the bundle --except the one that is being executed since the offer list is locked
    for (uint i; i < bundle.length; i++) {
      if (bundle[i].offerId != skipId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(bundle[i].inbound_tkn),
          tickSpacing: bundle[i].tick
        });

        /// if trying to update an offer that is on a locked offer list, update will fail.
        /// This could happen if an offer logic from offer list (A,B) is triggering a market order in offer list (A,C) and the offer one is trying to update is in the currently locked offer list (A,B)
        /// In this case the offer on (A,B) is promising too much A's.
        /// This is not guarantee to make it fail when taken because the offer could be sourcing liquidity from a pool that has access to more tokens than the amplified volume.
        /// we cannot retract it as well, so we tell it to renege in order to avoid over delivery.
        /// note potential griefing could be:
        /// 1. place a dummy offer on (A,B) that triggers a market order on (A,C) up to an offer that is part of a bundle (A, [B,C])
        /// 2. At the end of the market order attacker collects the bounty of the offer of the bundle that is now expired on the (A,B) offer list.
        /// Griefing would be costly however because the market order on (A,C) needs to reach and partly consumes the offer of the bundle
        if (MGV.locked(olKey_i)) {
          _setExpiry(olKey_i.hash(), bundle[i].offerId, block.timestamp);
        } else {
          Offer offer_i = MGV.offers(olKey_i, bundle[i].tick);
          // if offer_i was previously retracted, it should no longer be considered part of the bundle.
          if (offer_i.gives() != 0) {
            OfferDetail offerDetail_i = MGV.offerDetails(olKey_i, bundle[i].offerId);
            // Updating offer_i
            OfferArgs memory args;
            args.olKey = olKey_i;
            args.tick = offer_i.tick(); // same price
            args.gives = outboundVolume; // new volume
            args.gasreq = offerDetail_i.gasreq();
            args.noRevert = true;
            // call below might revert if:
            // - outboundVolume is now below density on the corresponding offer list
            // - offer provision is no longer sufficient to match mangrove's gasprice
            // - Market is now innactive
            // - Mangrove is dead
            // we then retract the offer (note the offer list cannot be locked at this stage)
            bytes32 reason = _updateOffer(args, bundle[i].offerId);
            if (reason != REPOST_SUCCESS) {
              // we do not deprovision, owner funds can be retrieved on a pull basis later on
              _retractOffer(olKey_i, bundle[i].offerId, false);
            }
            if (updateExpiry) {
              _setExpiry(olKey_i.hash(), bundle[i].offerId, expiryDate);
            }
          }
        }
      }
    }
  }

  ///@notice public function to update a bundle of offers
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@param outboundVolume the new volume that each offer of the bundle should now offer
  ///@param updateExpiry whether the update also changes expiry date of the bundle
  ///@param expiryDate the new date (if `updateExpiry` is true) for the expiry of the offers of the bundle. 0 for no expiry
  ///@dev each offer of the bundle can still be updated individually through `super.updateOffer`
  function updateBundle(
    uint bundleId,
    IERC20 outbound_tkn,
    uint outboundVolume,
    bool updateExpiry,
    uint expiryDate // use only if `updateExpiry` is true
  ) external {
    BundledOffer[] memory bundle = __bundles[bundleId];
    require(ownerOf(bundle, outbound_tkn) == msg.sender, "MgvAmplifier/unauthorized");
    _updateBundle(bundle, outbound_tkn, 0, outboundVolume, updateExpiry, expiryDate);
  }

  ///@notice retracts a bundle of offers
  ///@param bundle the bundle whose offers need to be retracted
  ///@param outbound_tkn the outbound token of the bundle
  ///@param skipId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param deprovision whether retracting the offer should also deprovision offers on Mangrove
  ///@return freeWei the amount of native tokens on this contract's balance that belong to msg.sender
  function _retractBundle(BundledOffer[] memory bundle, IERC20 outbound_tkn, uint skipId, bool deprovision)
    internal
    returns (uint freeWei)
  {
    for (uint i; i < bundle.length; i++) {
      if (bundle[i].offerId != skipId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(bundle[i].inbound_tkn),
          tickSpacing: bundle[i].tick
        });
        freeWei += _retractOffer(olKey_i, bundle[i].offerId, deprovision);
      }
    }
  }

  ///@notice public method to retract a bundle of offers
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@dev offers can be retracted individually using `super.retractOffer`
  function retractBundle(uint bundleId, IERC20 outbound_tkn) external {
    BundledOffer[] memory bundle = __bundles[bundleId];
    require(ownerOf(bundle, outbound_tkn) == msg.sender, "MgvAmplifier/unauthorized");
    uint freeWei = _retractBundle(bundle, outbound_tkn, 0, true);
    (bool noRevert,) = msg.sender.call{value: freeWei}("");
    require(noRevert, "MgvAmplifier/weiTransferFail");
  }

  ///@inheritdoc MangroveOffer
  ///@dev updating offer bundle in makerExecute rather than in makerPosthook to avoid griefing: an adversarial offer logic could collect the bounty of the bundle by taking the not yet updated offers during its execution.
  ///@dev the risk of updating the bundle during makerExecute is that any revert will make the trade revert, so one needs to make sure it does not happen (by catching potential reverts, assuming no "out of gas" is thrown)
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint) {
    // this will use offer owner's router to pull `amount` to this contract
    uint missing = super.__get__(amount, order);

    // we know take care of updating the other offers that are part of the same bundle
    uint bundleId = __bundleIdOfOfferId[order.olKey.hash()][order.offerId];
    BundledOffer[] memory bundle = __bundles[bundleId];
    // if funds are missing, the trade will fail and one should retract the bundle
    // otherwise we update the bundle to the new volume
    if (missing == 0) {
      _updateBundle(
        bundle,
        IERC20(order.olKey.outbound_tkn),
        order.offerId,
        order.offer.gives() - order.takerWants,
        false, // no expiry update
        0
      );
    } else {
      // not deprovisionning to save execution gas
      _retractBundle(bundle, IERC20(order.olKey.outbound_tkn), order.offerId, false);
    }
    return missing;
  }
}
