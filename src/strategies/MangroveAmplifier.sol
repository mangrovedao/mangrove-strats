// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {
  RenegingForwarder,
  MangroveOffer,
  RouterProxyFactory,
  RouterProxy
} from "@mgv-strats/src/strategies/offer_forwarder/RenegingForwarder.sol";
import {TransferLib, AbstractRouter, RL} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {SmartRouter, AbstractRoutingLogic} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {TickLib, Tick} from "@mgv/lib/core/TickLib.sol";

///@title MangroveAmplifier. A strat that implements "liquidity amplification". It allows offer owner to post offers on multiple markets with the same collateral.
/// The strat is implemented such that it cannot give more than the total amplified volume even if it is approved to spend more and has access to more funds.
/// e.g an amplified offer gives A for some amount of B, C or D. If taken on the (A,C) market, the (A,B) and (A,D) offers should now either:
/// - offer the same amount of A than the residual (A,B) offer -including 0 if the offer was completely filled
/// - or be reneging on trade (this happens only in a particular scenario in order to avoid over spending).
/// Amplified offers have a global expiry date and each offer of the bundle have an individual one. An offer reneges on trade if either the bundle is expired or if their individual expiry date has been reached, or the max volume is surpassed.

contract MangroveAmplifier is RenegingForwarder {
  ///@notice offer bundle identifier
  uint private __bundleId;

  struct BundledOffer {
    IERC20 inbound_tkn; // the inbound token of the offer in the bundle
    uint tickSpacing; // the tick spacing of the offer list in which the offer is posted
    uint offerId; // the offer of the offer
  }

  ///@notice maps a `bundleId` to a set of bundled offers
  mapping(uint bundleId => BundledOffer[]) private __bundles;

  ///@notice maps an offer list key hash and an offerId to the bundle in which this offer is.
  mapping(bytes32 olKeyHash => mapping(uint offerId => uint bundleId)) private __bundleIdOfOfferId;

  ///@notice logs beginning of bundle creation
  ///@param bundleId bundle identifier
  event InitBundle(uint indexed bundleId);

  ///@notice logs end of bundle creation
  ///@dev to know which offer are part of the bundle one needs to track `NewOwnedOffer(olKeyHash, offerId, owner)` emitted in between `InitBundle` and `EndBundle`
  ///@dev the expiry date of the bundle is given by the logs `SetReneging(olKeyHash, offerId, expiryDate, maxVolume)` of each offer of the bundle (all dates are the same).
  event EndBundle();

  ///@notice MangroveAmplifier is a Forwarder logic with a smart router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param factory the router proxy factory used to deploy or retrieve user routers
  constructor(IMangrove mgv, RouterProxyFactory factory) RenegingForwarder(mgv, factory, new SmartRouter()) {}

  struct FixedBundleParams {
    IERC20 outbound_tkn; //the promised asset for all offers of the bundle
    uint outVolume; // how much assets each offer promise
    AbstractRoutingLogic outboundLogic; // the logic to manage liquidity sourcing.  Use `AbstractRoutingLogic(address(0))` for simple routing.
    uint expiryDate; // date of expiration of each offer of the bundle. Use 0 for no expiry.
  }

  struct VariableBundleParams {
    Tick tick; // the price tick of the offer
    uint gasreq; // the gas required by this offer (gas may differ between offer because of different routing strategies)
    uint provision; // the portion of `msg.value` that should be allocated to the provision of this offer
    uint tickSpacing; // the tick spacing parameter that charaterizes the offer list to which this offer should be posted.
    AbstractRoutingLogic inboundLogic; //the logics to manage liquidity targetting for this offer of the bundle. Use `AbstractRouter(address(0))` for simple routing.
    IERC20 inbound_tkn; // the inbound token this offer expects
  }

  struct HeapVarsNewBundle {
    uint availableProvision; // remaining funds to provision offers of the bundle
    RouterProxy proxy; // address of the offer owner router proxy (to be called when setting routing logics)
    uint provision_i; // provision allocated for the current offer
    OLKey olKey_i; // olKey for the i^th offer
    bytes32 olKeyHash_i; // hash of the above olKey
    RL.RoutingOrder routingOrder_i; // routing order to set the logic for the i^th offer
    BundledOffer bundledOffer_i; // i^th offer of the bundle
  }

  ///@inheritdoc RenegingForwarder
  ///@notice reneges on any offer of a bundle if the bundle expiry date is passed or if the offer's expiry date is passed or if the offer volume is higher than max volume.
  ///@dev we use expiry map to represent both offer expiry (in which case olKeyHash and offerId need to be provided) and bundle expiry
  /// `reneging(bytes32(0),i)` corresponds to the expiry date of the bundle `i`. Expiry volume also lies here but is unused because volumes are different for each offer of the bundle.
  /// `reneging(olKey.hash(), i)` corresponds to the expiry date and max volume of offer `i` in the offer list identified by `olKey`.
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32 retdata) {
    // checks expiry date and max offered volume of order.offerId first
    // if expired or over promising the call below will revert
    retdata = super.__lastLook__(order);
    // checks now whether there is a bundle wide expiry date
    uint bundleId = __bundleIdOfOfferId[order.olKey.hash()][order.offerId];
    uint bundleExpiryDate = reneging(bytes32(0), bundleId).date;
    require(bundleExpiryDate == 0 || bundleExpiryDate > block.timestamp, "MgvAmplifier/expiredBundle");
  }

  ///@notice bundle wide expiry date setter
  ///@param bundleId the id of the bundle whose expiry date is to be set
  ///@param date the date of expiry (use 0 for no expiry)
  ///@dev and offer logic will renege if either the offer's expiry date is passed or it belongs to a bundle whose expiry date has passed.
  /// * The volume is set to 0 because it is unused for bundle.
  function _setBundleExpiry(uint bundleId, uint date) internal {
    _setReneging(0, bundleId, date, 0);
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
    // fetching owner's router
    (vars.proxy,) = ROUTER_FACTORY.instantiate(msg.sender, ROUTER_IMPLEMENTATION);

    for (uint i; i < vr.length; i++) {
      require(vr[i].provision <= vars.availableProvision, "MgvAmplifier/NotEnoughProvisions");
      // making sure no native token remains in the strat
      // note if `vars.provision_i` is insufficient to cover `gasreq=vr[i].gasreq` the call below will revert
      vars.provision_i = i == vr.length - 1 ? vars.availableProvision : vr[i].provision;
      vars.olKey_i = OLKey({
        outbound_tkn: address(fx.outbound_tkn),
        inbound_tkn: address(vr[i].inbound_tkn),
        tickSpacing: vr[i].tickSpacing
      });
      // memoizing hash
      vars.olKeyHash_i = vars.olKey_i.hash();
      // posting new offer on Mangove
      (vars.bundledOffer_i.offerId,) = _newOffer(
        OfferArgs({
          olKey: vars.olKey_i,
          tick: vr[i].tick,
          gives: fx.outVolume,
          gasreq: vr[i].gasreq,
          gasprice: 0, // ignored in Forwarder strats
          fund: vars.provision_i,
          noRevert: false // revert if unable to post
        }),
        msg.sender
      );

      vars.routingOrder_i.olKeyHash = vars.olKeyHash_i;
      vars.routingOrder_i.offerId = vars.bundledOffer_i.offerId;

      // Setting logic to push inbound tokens of the offer
      if (address(vr[i].inboundLogic) != address(0)) {
        vars.routingOrder_i.token = vr[i].inbound_tkn;
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder_i, vr[i].inboundLogic);
      }

      // Setting logic to pull outbound tokens of the offer
      if (address(fx.outboundLogic) != address(0)) {
        vars.routingOrder_i.token = fx.outbound_tkn;
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder_i, fx.outboundLogic);
      }

      // Updating remaining available native tokens for provisions
      vars.availableProvision -= vars.provision_i;

      // pushing to storage the new bundle
      vars.bundledOffer_i.tickSpacing = vr[i].tickSpacing;
      vars.bundledOffer_i.inbound_tkn = vr[i].inbound_tkn;
      __bundleIdOfOfferId[vars.olKeyHash_i][vars.bundledOffer_i.offerId] = freshBundleId;
      __bundles[freshBundleId].push(vars.bundledOffer_i);
    }
    // Setting bundle wide expiry date if required
    // olKeyHash = bytes32(0) indicates that expiry is for the whole bundle
    if (fx.expiryDate != 0) {
      _setBundleExpiry(freshBundleId, fx.expiryDate);
    }
    emit EndBundle();
  }

  ///@notice gets the offers that are bundled under the same `bundleId`
  ///@param bundleId the id of the bundle
  ///@return bundle of offers
  function offersOf(uint bundleId) external view returns (BundledOffer[] memory) {
    return __bundles[bundleId];
  }

  ///@notice retrieves bundle owner from offer owner
  ///@param bundle of offers whose owner is queried
  ///@param outbound_tkn of the bundle
  ///@return address of the owner of the bundle
  ///@dev call assume bundle has at least one offer.
  function _extractOwnerOf(BundledOffer[] memory bundle, IERC20 outbound_tkn) internal view returns (address) {
    OLKey memory olKey = OLKey({
      outbound_tkn: address(outbound_tkn),
      inbound_tkn: address(bundle[0].inbound_tkn),
      tickSpacing: bundle[0].tickSpacing
    });
    return (ownerOf(olKey.hash(), bundle[0].offerId));
  }

  ///@notice owner of the bundle (is owner of all its offers)
  ///@param bundleId the bundle id
  ///@param outbound_tkn the outbound token of the offer bundle
  ///@return address of the owner of the bundle
  function ownerOf(uint bundleId, IERC20 outbound_tkn) external view returns (address) {
    return _extractOwnerOf(__bundles[bundleId], outbound_tkn);
  }

  ///@notice updates a bundle of offers, possibly during the execution of the logic of one of them.
  ///@param bundle the offer bundle to update
  ///@param outbound_tkn the outbound token of the bundle
  ///@param skipOlKeyHash skip updating bundle offer if it is on this offer list (hash) -- it is locked for reentrancy
  ///@param outboundVolume the new volume that each offer of the bundle should now offer
  function _updateBundle(BundledOffer[] memory bundle, IERC20 outbound_tkn, bytes32 skipOlKeyHash, uint outboundVolume)
    internal
  {
    // updating outbound volume for all offers of the bundle --except the one that is being executed since the offer list is locked
    for (uint i; i < bundle.length; i++) {
      OLKey memory olKey_i = OLKey({
        outbound_tkn: address(outbound_tkn),
        inbound_tkn: address(bundle[i].inbound_tkn),
        tickSpacing: bundle[i].tickSpacing
      });
      bytes32 olKeyHash_i = olKey_i.hash();
      if (skipOlKeyHash != olKeyHash_i) {
        try MGV.offers(olKey_i, bundle[i].tickSpacing) returns (Offer offer_i) {
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
            // call below might fail to update when:
            // - outboundVolume is now below density on the corresponding offer list
            // - offer provision is no longer sufficient to match mangrove's gasprice
            // - offer list is now inactive
            // - Mangrove is dead
            bytes32 reason = _updateOffer(args, bundle[i].offerId);
            if (reason != REPOST_SUCCESS) {
              // we do not deprovision, owner funds can be retrieved on a pull basis later on
              _retractOffer(olKey_i, bundle[i].offerId, false, false);
            }
          }
        } catch {
          /// if trying to update an offer that is on a locked offer list, call to `mgv.offers` will throw.
          /// Since it is not the offer list whose hash is `skipOlKeyHash` the only scenario is the following:
          /// an offer logic from offer list (A,B) is triggering a market order in offer list (A,C) and the offer one is trying to update is in the currently locked offer list (A,B)
          /// In this case the offer on (A,B) is promising too much A's.
          /// This is not guarantee to make it fail when taken because the offer could be sourcing liquidity from a pool that has access to more tokens than the amplified volume.
          /// we cannot retract it as well, so we tell it to renege in order to avoid over delivery.
          /// note potential griefing could be:
          /// 1. place a dummy offer on (A,B) that triggers a market order on (A,C) up to an offer that is part of a bundle (A, [B,C])
          /// 2. At the end of the market order attacker collects the bounty of the offer of the bundle that is now expired on the (A,B) offer list.
          /// Griefing would be costly however because the market order on (A,C) needs to reach and partly consumes the offer of the bundle
          Condition memory cond = reneging(olKeyHash_i, bundle[i].offerId);
          cond.volume = uint96(outboundVolume);
          _setReneging(olKeyHash_i, bundle[i].offerId, cond.date, cond.volume);
        }
      }
    }
  }

  ///@notice public function to update common parameters of a bundle of offers (i.e outbound volume and expiry date)
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@param outboundVolume the new volume that each offer of the bundle should now offer. Use 0 to skip volume update.
  ///@param updateExpiry whether the update also changes expiry date of the bundle
  ///@param expiryDate the new date (if `updateExpiry` is true) for the expiry of the offers of the bundle. 0 for no expiry
  ///@dev each offer of the bundle can still be updated individually through `super.updateOffer`
  function updateBundle(
    uint bundleId,
    IERC20 outbound_tkn,
    uint outboundVolume, // use 0 if only updating expiry
    bool updateExpiry,
    uint expiryDate // use only if `updateExpiry` is true
  ) external {
    BundledOffer[] memory bundle = __bundles[bundleId];
    require(_extractOwnerOf(bundle, outbound_tkn) == msg.sender, "MgvAmplifier/unauthorized");
    if (outboundVolume > 0) {
      _updateBundle(bundle, outbound_tkn, bytes32(0), outboundVolume);
    }
    if (updateExpiry) {
      _setBundleExpiry(bundleId, expiryDate);
    }
  }

  ///@notice retracts a bundle of offers
  ///@param bundle the bundle whose offers need to be retracted
  ///@param outbound_tkn the outbound token of the bundle
  ///@param skipOlKeyHash skip updating bundle offer if it is on this offer list (hash) -- it is locked for reentrancy
  ///@param deprovision whether retracting the offer should also deprovision offers on Mangrove
  ///@return freeWei the amount of native tokens on this contract's balance that belong to msg.sender
  function _retractBundle(BundledOffer[] memory bundle, IERC20 outbound_tkn, bytes32 skipOlKeyHash, bool deprovision)
    internal
    returns (uint freeWei)
  {
    for (uint i; i < bundle.length; i++) {
      OLKey memory olKey_i = OLKey({
        outbound_tkn: address(outbound_tkn),
        inbound_tkn: address(bundle[i].inbound_tkn),
        tickSpacing: bundle[i].tickSpacing
      });
      bytes32 olKeyHash_i = olKey_i.hash();
      if (skipOlKeyHash != olKeyHash_i) {
        bytes32 status;
        (freeWei, status) = _retractOffer(olKey_i, bundle[i].offerId, true, deprovision);
        if (status != bytes32(0)) {
          // this only happens if offer `i` of the bundle is in a locked offer list --see `_updateBundle`
          _setReneging(olKeyHash_i, bundle[i].offerId, block.timestamp, 0);
        }
      }
    }
  }

  ///@notice public method to retract a bundle of offers
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@return freeWei the amount of native tokens that has been sent to to msg.sender
  ///@dev offers can be retracted individually using `super.retractOffer`
  function retractBundle(uint bundleId, IERC20 outbound_tkn) external returns (uint freeWei) {
    BundledOffer[] memory bundle = __bundles[bundleId];
    require(_extractOwnerOf(bundle, outbound_tkn) == msg.sender, "MgvAmplifier/unauthorized");
    freeWei = _retractBundle(bundle, outbound_tkn, bytes32(0), true);
    (bool noRevert,) = msg.sender.call{value: freeWei}("");
    require(noRevert, "MgvAmplifier/weiTransferFail");
  }

  ///@inheritdoc MangroveOffer
  ///@dev updating offer bundle in makerExecute rather than in makerPosthook to avoid griefing: an adversarial offer logic could collect the bounty of the bundle by taking the not yet updated offers during its execution.
  ///@dev the risk of updating the bundle during makerExecute is that any revert will make the trade revert, so one needs to make sure it does not happen (by catching potential reverts, assuming no "out of gas" is thrown)
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint) {
    // `__lastLook__` was already called so we know order is neither expired nor over promising
    // this will use offer owner's router to pull `amount` to this contract
    uint missing = super.__get__(amount, order);

    // we now take care of updating the other offers that are part of the same bundle
    // this update might fail if the offer list is locked (see `_updateBundle`)
    bytes32 olKeyHash = order.olKey.hash();
    uint bundleId = __bundleIdOfOfferId[olKeyHash][order.offerId];
    BundledOffer[] memory bundle = __bundles[bundleId];
    // if funds are missing, the trade will fail and one should retract the bundle
    // we also retract the bundle if there is no more outbound volume to offer (this avoids reverting of updateOffer for a too low density)
    // otherwise we update the bundle to the new volume
    uint newOutVolume = order.offer.gives() - order.takerWants;
    if (missing == 0 && newOutVolume > 0) {
      _updateBundle(bundle, IERC20(order.olKey.outbound_tkn), olKeyHash, newOutVolume);
    } else {
      // not deprovisionning to save execution gas
      _retractBundle(bundle, IERC20(order.olKey.outbound_tkn), olKeyHash, false);
    }
    return missing;
  }
}
