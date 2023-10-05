// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Forwarder, IMangrove, IERC20} from "mgv_strat_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ILiquidityProvider} from "mgv_strat_src/strategies/interfaces/ILiquidityProvider.sol";
import {AbstractRouter, MonoRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {Dispatcher} from "mgv_strat_src/strategies/routers/integrations/Dispatcher.sol";
import {MgvLib, OLKey} from "mgv_src/core/MgvLib.sol";
import {Tick} from "mgv_lib/core/TickLib.sol";
import {MangroveOffer} from "mgv_strat_src/strategies/MangroveOffer.sol";

/// @title `OfferDispatcher` is a forwarder contract for Mangrove using the `Dispatcher` router.
/// @notice This contract makes use of the dispatcher router to route offers to the correct router.
/// @dev This contract deploys and auto binds a `Dispatcher` router.
contract OfferDispatcher is ILiquidityProvider, Forwarder {
  /// @notice contract's constructor
  /// @param mgv The Mangrove contract
  /// @param deployer The address to set as admin
  constructor(IMangrove mgv, address deployer) Forwarder(mgv, new Dispatcher(), 30_000) {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router_.setAdmin(deployer);
    }
  }

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

  ///@notice creates a new offer on Mangrove with the default gas requirement
  ///@param olKey the offer list key.
  ///@param tick the tick
  ///@param gives the amount of inbound tokens the offer maker gives for a complete fill
  ///@return offerId the Mangrove offer id.
  function newOffer(OLKey memory olKey, Tick tick, uint gives) external payable returns (uint offerId) {
    return newOffer(olKey, tick, gives, offerGasreq(IERC20(olKey.outbound_tkn), msg.sender));
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

  ///@notice updates an offer existing on Mangrove (not necessarily live) with the default gas requirement
  ///@param olKey the offer list key.
  ///@param tick the tick
  ///@param gives the new amount of inbound tokens the offer maker gives for a complete fill
  ///@param offerId the id of the offer in the offer list.
  function updateOffer(OLKey memory olKey, Tick tick, uint gives, uint offerId) public payable {
    address owner = ownerOf(olKey.hash(), offerId);
    require(owner == msg.sender, "OfferForwarder/unauthorized");
    updateOffer(olKey, tick, gives, offerId, offerGasreq(IERC20(olKey.outbound_tkn), msg.sender));
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision)
    public
    mgvOrOwner(olKey.hash(), offerId)
    returns (uint freeWei)
  {
    return _retractOffer(olKey, offerId, deprovision);
  }

  /// @inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 maker_data)
    internal
    override
    returns (bytes32 data)
  {
    data = super.__posthookSuccess__(order, maker_data);
    require(
      data == "posthook/reposted" || data == "posthook/filled",
      data == "mgv/insufficientProvision"
        ? "mgv/insufficientProvision"
        : (data == "mgv/writeOffer/density/tooLow" ? "mgv/writeOffer/density/tooLow" : "posthook/failed")
    );
  }

  /// @notice Calls a function of a specific router implementation
  /// @dev the function that receive the call must have the data as follows (address, IERC20, bytes calldata)
  /// * only the reserveId can call this function
  /// @param selector The selector of the function to call
  /// @param reserveId The reserveId to call the function on
  /// @param token The token to call the function on
  /// @param data The data to call the function with
  function callDispatcherSpecificFunction(bytes4 selector, address reserveId, IERC20 token, bytes calldata data)
    external
    onlyCaller(reserveId)
  {
    Dispatcher dispatcher = Dispatcher(address(router()));
    dispatcher.callRouterSpecificFunction(selector, reserveId, token, data);
  }

  /// @notice Sets a route for a given token and reserveId
  /// @dev calls a function with the same signature on the router
  /// * only the reserveId can call this function
  /// @param token The token to set the route for
  /// @param reserveId The reserveId to set the route for
  /// @param route The route to set
  function setRoute(IERC20 token, address reserveId, MonoRouter route) external onlyCaller(reserveId) {
    Dispatcher dispatcher = Dispatcher(address(router()));
    dispatcher.setRoute(token, reserveId, route);
  }
}
