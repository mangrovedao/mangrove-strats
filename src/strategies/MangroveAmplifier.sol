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

  // ///@notice maps a `bundleId` to the set of inbound_tokens of the bundle
  // mapping(uint bundleId => IERC20[] inbound_tkns) private __inboundTknsOfBundleId;

  // ///@notice maps a `bundleId` to the set of pairs (tickSpacing, offerId) of the bundle
  // mapping(uint bundleId => uint[2][] ticks_offerIds) private __ticks_offerIdsOfBundleId;

  struct BundleOfferInfo {
    uint tickSpacing;
    uint offerId;
    IERC20 inbound_tkn;
  }

  struct BundleInfo {
    uint expiry;
    BundleOfferInfo[] offerInfos;
  }

  ///@notice maps a bundleId to the bundle info
  mapping(uint bundleId => BundleInfo) private __bundleInfoOfBundleId;

  ///@notice maps an offer list key hash and an offerId to the bundle in which this offer is.
  ///@dev given an incoming taker order  `(offerId, olKey)` one may retrieve all offers that are in the same bundle doing:
  /// 1. ` bundleId = __bundleIdOfOfferId[olKey.hash][offerId]`
  /// 2. `[tick_j, offerId_j] = __ticks_offerIdsOfBundleId[bundleId][j]`
  /// 3. `inbound_j` = __inboundTknsOfBundleId[bundleId][j]`
  /// for all j <= `__ticks_offerIdsOfBundleId[bundleId].length`
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

  struct HeapVarsNewBundle {
    uint availableProvision;
    uint provision;
    uint offerId;
    OLKey olKey;
    bytes32 olKeyHash;
    RouterProxy proxy;
    RL.RoutingOrder routingOrder;
  }

  ///@notice parameters of an offer of the bundle
  ///@param inVolume the amount of inbound token the i^th offer of the bundle wants
  ///@param gasreq the gas required by the i^th offer (gas may differ between offer because of different routing strategies)
  ///@param provision the portion of `msg.value` that should be allocated to the provision of the i^th offer
  ///@param tick the tick spacing parameter that charaterizes the offer list to which the offer should be posted.
  struct OfferParams {
    uint inVolume;
    uint gasreq;
    uint provision;
    uint tick;
    IERC20 inbound_tkn;
    AbstractRouter inboundLogic;
  }

  ///@param outbound_tkn the promised asset for all offers of the bundle
  ///@param outboundLogic the logic to manage liquidity sourcing.  Use `AbstractRouter(address(0))` for simple routing.
  ///@param outVolume how much assets each offer promise
  ///@param expiryDate date of expiration of each offer of the bundle. Use 0 for no expiry.
  ///@param inboundTkns an array of length `n` such that `inboundTkns[i]` is the inbound of the i^th offer of the bundle
  ///@param params the offers parameters such that `params[i]=[inVolume, gasreq, provision, tick]` where:
  /// * `inVolume` is the amount of inbound token the i^th offer of the bundle wants
  /// * `gasreq` is the gas required by the i^th offer (gas may differ between offer because of different routing strategies)
  /// * `provision` is the portion of `msg.value` that should be allocated to the provision of the i^th offer
  /// * `tick` is the tick spacing parameter that charaterizes the offer list to which the offer should be posted.
  ///@param inboundLogics the logics to manage liquidity targetting for each offer of the bundle. Use `AbstractRouter(address(0))` for simple routing.
  struct BundleArgs {
    IERC20 outbound_tkn;
    uint outVolume;
    AbstractRouter outboundLogic; // AbstractRouter(address(0)) for SimpleRouter behavior.
    uint expiryDate; // 0 for no expiry
    OfferParams[] params; // params[0]: inVolume, params[1] = gasreq, params[2] = provision, params[3] = tick
  }

  ///@inheritdoc ExpirableForwarder
  function _setExpiry(bytes32, uint, uint) internal virtual override {
    revert("MangroveAmplifier/NoSingleOfferExpiry");
  }

  ///@notice posts bundle of offers on Mangrove so as to amplify a certain volume of outbound tokens
  ///@param args cf struct BundleArgs
  ///@return freshBundleId the bundle identifier
  function newBundle(BundleArgs calldata args) public payable returns (uint freshBundleId) {
    HeapVarsNewBundle memory vars;
    freshBundleId = __bundleId++;

    emit InitBundle(freshBundleId);

    BundleInfo storage bundleInfo = __bundleInfoOfBundleId[freshBundleId];

    // setting bundle expiry
    if (args.expiryDate != 0) {
      bundleInfo.expiry = args.expiryDate;
    }

    // vars.ticks_offerIds = new uint[2][](args.params.length);
    vars.availableProvision = msg.value;

    // creating the router proxy for the current user
    (vars.proxy,) = ROUTER_FACTORY.instantiate(msg.sender, ROUTER_IMPLEMENTATION);

    for (uint i; i < args.params.length; i++) {
      require(args.params[i].provision <= vars.availableProvision, "MgvAmplifier/NotEnoughProvisions");
      // making sure no native token remains in the strat
      // note if `vars.provision` is insufficient to cover `gasreq=params[2][i]` the call below will revert
      vars.provision = i == args.params.length - 1 ? vars.availableProvision : args.params[i].provision;
      vars.olKey = OLKey({
        outbound_tkn: address(args.outbound_tkn),
        inbound_tkn: address(args.params[i].inbound_tkn),
        tickSpacing: args.params[i].tick
      });
      // posting new offer on Mangove
      (vars.offerId,) = _newOffer(
        OfferArgs({
          olKey: vars.olKey,
          tick: TickLib.tickFromVolumes(args.params[i].inVolume, args.outVolume),
          gives: args.outVolume,
          gasreq: args.params[i].gasreq,
          gasprice: 0, // ignored in Forwarder strats
          fund: vars.provision,
          noRevert: false // revert if unable to post
        }),
        msg.sender
      );
      // Setting logic to push inbound tokens offer
      vars.routingOrder.token = args.params[i].inbound_tkn;
      vars.routingOrder.olKeyHash = vars.olKeyHash;
      vars.routingOrder.offerId = vars.offerId;

      if (args.params[i].inboundLogic != AbstractRouter(address(0))) {
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder, args.params[i].inboundLogic);
      }

      // Setting logic to pull outbount tokens for the same offer
      vars.routingOrder.token = args.outbound_tkn;
      if (args.outboundLogic != AbstractRouter(address(0))) {
        SmartRouter(address(vars.proxy)).setLogic(vars.routingOrder, args.outboundLogic);
      }

      vars.olKeyHash = vars.olKey.hash();
      if (args.expiryDate != 0) {
        _setExpiry(vars.olKeyHash, vars.offerId, args.expiryDate);
      }
      vars.availableProvision -= args.params[i].provision;
      // vars.ticks_offerIds[i] = [args.params[i].tick, vars.offerId];
      __bundleIdOfOfferId[vars.olKeyHash][vars.offerId] = freshBundleId;
      bundleInfo.offerInfos.push(
        BundleOfferInfo({
          tickSpacing: args.params[i].tick,
          offerId: vars.offerId,
          inbound_tkn: args.params[i].inbound_tkn
        })
      );
    }

    emit EndBundle();
  }

  ///@notice given a bundle identifier and its outbound token, fetches the inbound tokens, the tick spacings and the offer ids of the offers of that bundle
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@return bundleInfo the bundle info
  ///@return owner the owner of all bundle's offers.
  function _getBundleMaps(uint bundleId, IERC20 outbound_tkn)
    internal
    view
    returns (BundleInfo memory bundleInfo, address owner)
  {
    // inboundTkns = __inboundTknsOfBundleId[bundleId];
    // ticks_offerIds = __ticks_offerIdsOfBundleId[bundleId];

    bundleInfo = __bundleInfoOfBundleId[bundleId];

    // msg.sender owns the bundle if and only if it owns one of its offers. We check the first offer of the bundle
    OLKey memory olKey_0 = OLKey({
      outbound_tkn: address(outbound_tkn),
      inbound_tkn: address(bundleInfo.offerInfos[0].inbound_tkn),
      tickSpacing: bundleInfo.offerInfos[0].tickSpacing
    });
    owner = ownerOf(olKey_0.hash(), bundleInfo.offerInfos[0].offerId);
  }

  ///@notice updates a bundle of offers, possibly during the execution of the logic of one of them.
  ///@param outbound_tkn the outbound token of the bundle
  ///@param offerId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param offerArgs The array of offer arguments such that `offerArgs[i] = UpdateBundleOfferArgs(tickSpacing_i, offerId_i, inbound_tkn_i)`
  ///@param outboundVolume the new volume that each offer of the bundle should now offer
  ///@param updateExpiry whether the update also changes expiry date of the bundle
  ///@param expiryDate the new date (if `updateExpiry` is true) for the expiry of the offers of the bundle. 0 for no expiry
  function _updateBundle(
    IERC20 outbound_tkn,
    uint offerId,
    BundleOfferInfo[] memory offerArgs,
    uint outboundVolume,
    bool updateExpiry,
    uint expiryDate
  ) internal {
    // updating outbound volume for all offers of the bundle --except the one that is being executed since the offer list is locked
    for (uint i; i < offerArgs.length; i++) {
      if (offerArgs[i].offerId != offerId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(offerArgs[i].inbound_tkn),
          tickSpacing: offerArgs[i].tickSpacing
        });
        Offer offer_i = MGV.offers(olKey_i, offerArgs[i].offerId);
        // if offer_i was previously retracted, it should no longer be considered part of the bundle.
        if (offer_i.gives() != 0) {
          OfferDetail offerDetail_i = MGV.offerDetails(olKey_i, offerArgs[i].offerId);
          // Updating offer_i
          OfferArgs memory args;
          args.olKey = olKey_i;
          args.tick = offer_i.tick(); // same price
          args.gives = outboundVolume; // new volume
          args.gasreq = offerDetail_i.gasreq();
          args.noRevert = true;
          // call below will retract the offer without reverting if update fails (for instance if the density it too low)
          _updateOffer(args, offerArgs[i].offerId);
          if (updateExpiry) {
            _setExpiry(olKey_i.hash(), offerArgs[i].offerId, expiryDate);
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
    (BundleInfo memory bundleInfo, address owner) = _getBundleMaps(bundleId, outbound_tkn);
    require(owner == msg.sender, "MgvAmplifier/unauthorized");
    _updateBundle(outbound_tkn, 0, bundleInfo.offerInfos, outboundVolume, updateExpiry, expiryDate);
  }

  ///@notice retracts a bundle of offers
  ///@param outbound_tkn the outbound token of the bundle
  ///@param offerId the offer identifier that is being executed if the function is called during an offer logic's execution. Is 0 otherwise
  ///@param offerArgs The array of offer arguments such that `offerArgs[i] = UpdateBundleOfferArgs(tickSpacing_i, offerId_i, inbound_tkn_i)`
  ///@param deprovision whether retracting the offer should also deprovision offers on Mangrove
  ///@return freeWei the amount of native tokens on this contract's balance that belong to msg.sender
  function _retractBundle(IERC20 outbound_tkn, uint offerId, BundleOfferInfo[] memory offerArgs, bool deprovision)
    internal
    returns (uint freeWei)
  {
    for (uint i; i < offerArgs.length; i++) {
      if (offerArgs[i].offerId != offerId) {
        OLKey memory olKey_i = OLKey({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(offerArgs[i].inbound_tkn),
          tickSpacing: offerArgs[i].tickSpacing
        });
        freeWei += _retractOffer(olKey_i, offerArgs[i].offerId, deprovision);
      }
    }
  }

  ///@notice public method to retract a bundle of offers
  ///@param bundleId the bundle identifier
  ///@param outbound_tkn the outbound token of the bundle
  ///@dev offers can be retracted individually using `super.retractOffer`
  function retractBundle(uint bundleId, IERC20 outbound_tkn) external {
    (BundleInfo memory offerArgs, address owner) = _getBundleMaps(bundleId, outbound_tkn);
    require(owner == msg.sender, "MgvAmplifier/unauthorized");
    uint freeWei = _retractBundle(outbound_tkn, 0, offerArgs.offerInfos, true);
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
    BundleInfo storage bundleInfo = __bundleInfoOfBundleId[bundleId];
    BundleOfferInfo[] memory offerArgs = bundleInfo.offerInfos;
    // if funds are missing, the trade will fail and one should retract the bundle
    // otherwise we update the bundle to the new volume
    if (missing == 0) {
      _updateBundle(
        IERC20(order.olKey.outbound_tkn),
        order.offerId,
        offerArgs,
        order.offer.gives() - order.takerWants,
        false, // no expiry update
        0
      );
    } else {
      // not deprovisionning to save execution gas
      _retractBundle(IERC20(order.olKey.outbound_tkn), order.offerId, offerArgs, false);
    }
    return missing;
  }
}
