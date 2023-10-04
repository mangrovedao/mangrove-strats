// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Forwarder, IMangrove, IERC20} from "mgv_strat_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ILiquidityProvider} from "mgv_strat_src/strategies/interfaces/ILiquidityProvider.sol";
import {AbstractRouter, MonoRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {Dispatcher} from "mgv_strat_src/strategies/routers/integrations/Dispatcher.sol";
import {MgvLib, OLKey} from "mgv_src/core/MgvLib.sol";
import {Tick} from "mgv_lib/core/TickLib.sol";

contract OfferDispatcher is ILiquidityProvider, Forwarder {
  constructor(IMangrove mgv, address deployer) Forwarder(mgv, new Dispatcher(), 30_000) {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router_.setAdmin(deployer);
    }
  }

  // /// @inheritdoc ILiquidityProvider
  // function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq)
  //   public
  //   payable
  //   override
  //   returns (uint offerId)
  // {
  //   (offerId,) = _newOffer(
  //     OfferArgs({
  //       outbound_tkn: outbound_tkn,
  //       inbound_tkn: inbound_tkn,
  //       wants: wants,
  //       gives: gives,
  //       gasreq: gasreq,
  //       gasprice: 0,
  //       pivotId: pivotId,
  //       fund: msg.value,
  //       noRevert: false // propagates Mangrove's revert data in case of newOffer failure
  //     }),
  //     msg.sender
  //   );
  // }

  // function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
  //   public
  //   payable
  //   returns (uint offerId)
  // {
  //   return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq(outbound_tkn, msg.sender));
  // }

  // ///@inheritdoc ILiquidityProvider
  // ///@dev the `gasprice` argument is always ignored in `Forwarder` logic, since it has to be derived from `msg.value` of the call (see `_newOffer`).
  // function updateOffer(
  //   IERC20 outbound_tkn,
  //   IERC20 inbound_tkn,
  //   uint wants,
  //   uint gives,
  //   uint pivotId,
  //   uint offerId,
  //   uint gasreq
  // ) public payable override onlyOwner(outbound_tkn, inbound_tkn, offerId) {
  //   OfferArgs memory args;

  //   // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
  //   // it might be tempting to include `od.weiBalance` here but this will trigger a recomputation of the `gasprice`
  //   // each time a offer is updated.
  //   args.fund = msg.value; // if inside a hook (Mangrove is `msg.sender`) this will be 0
  //   args.outbound_tkn = outbound_tkn;
  //   args.inbound_tkn = inbound_tkn;
  //   args.wants = wants;
  //   args.gives = gives;
  //   args.gasreq = gasreq;
  //   args.pivotId = pivotId;
  //   args.noRevert = false; // will throw if Mangrove reverts
  //   // weiBalance is used to provision offer
  //   _updateOffer(args, offerId);
  // }

  // function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
  //   public
  //   payable
  // {
  //   address owner = ownerOf(outbound_tkn, inbound_tkn, offerId);
  //   require(owner == msg.sender, "OfferForwarder/unauthorized");
  //   updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq());
  // }

  // ///@inheritdoc ILiquidityProvider
  // function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
  //   public
  //   mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
  //   returns (uint freeWei)
  // {
  //   return _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  // }

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

  function setRoute(IERC20 token, address reserveId, MonoRouter route) external onlyCaller(reserveId) {
    Dispatcher dispatcher = Dispatcher(address(router()));
    dispatcher.setRoute(token, reserveId, route);
  }
}
