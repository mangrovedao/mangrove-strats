// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";
import {TakerOrderType} from "@mgv-strats/src/strategies/TakerOrderLib.sol";

///@title Interface for resting orders functionality.
interface IOrderLogic {
  ///@notice Information for creating a market order with a GTC or FOK semantics.
  ///@param olKey the offer list key.
  ///@param tick the tick
  ///@param orderType the order type
  ///@param fillVolume the volume to fill
  ///@param fillWants if true (usually when `TakerOrder` implements a "buy" on a market), the market order stops when `fillVolume` units of `olKey.outbound_tkn` have been obtained (fee included); otherwise (selling), the market order stops when `fillVolume` units of `olKey.inbound_tkn` have been sold.
  ///@param restingOrderGasreq the gas requirement for executing a resting order
  ///@param expiryDate timestamp (expressed in seconds since unix epoch) beyond which the order is no longer valid, 0 means forever
  ///@param offerId the id of an existing, dead offer owned by the taker to re-use for the resting order, 0 means no re-use.
  ///@param takerGivesLogic custom contract implementing routing logic for the tokens that are given by the taker order.
  ///@param takerWantsLogic custom contract implementing routing logic for the tokens that are wanted by the taker order.
  struct TakerOrder {
    OLKey olKey;
    Tick tick;
    TakerOrderType orderType;
    uint fillVolume;
    bool fillWants;
    uint expiryDate;
    uint offerId;
    uint restingOrderGasreq;
    AbstractRoutingLogic takerGivesLogic;
    AbstractRoutingLogic takerWantsLogic;
  }

  ///@notice Result of an order from the takers side.
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param bounty How much bounty was givin to the taker
  ///@param fee The fee paid by the taker
  ///@param offerId The id of the offer that was taken
  struct TakerOrderResult {
    uint takerGot;
    uint takerGave;
    uint bounty;
    uint fee;
    uint offerId;
    bytes32 offerWriteData;
  }

  ///@notice Information about the order.
  ///@param olKeyHash the hash of the offer list key. This could be found by the OrderStart event, but is needed for RPC call. This is indexed so that RPC calls can filter on it.
  ///@param taker The address of the taker. This could be found by the OrderStart event, but is needed for RPC call. This is indexed so that RPC calls can filter on it.
  ///@param tick The tick of the order. This is not needed for an indexer, as it can get it from the OrderStart event. It is only emitted for RPC calls.
  ///@param orderType type of the order.
  ///@param fillVolume the volume to fill. This is not needed for an indexer, as it can get it from the OrderStart event. It is only emitted for RPC calls.
  ///@param fillWants if true (buying), the market order stops when `fillVolume` units of `olKey.outbound_tkn` have been obtained (fee included); otherwise (selling), the market order stops when `fillVolume` units of `olKey.inbound_tkn` have been sold.
  ///@param offerId The optional offerId take was called with, 0 if not passed. This is not needed for an indexer. It is only emitted for RPC calls.
  ///@param takerGivesLogic custom contract implementing routing logic for the tokens that are given by the taker order.
  ///@param takerWantsLogic custom contract implementing routing logic for the tokens that are wanted by the taker order.
  ///@notice By emitting this data, an indexer will be able to tell that we are in the context of an mangroveOrder and keep track of what parameters were used to start the order.
  event MangroveOrderStart(
    bytes32 indexed olKeyHash,
    address indexed taker,
    Tick tick,
    TakerOrderType orderType,
    uint fillVolume,
    bool fillWants,
    uint offerId,
    AbstractRoutingLogic takerGivesLogic,
    AbstractRoutingLogic takerWantsLogic
  );

  ///@notice Indicates that the MangroveOrder has been completed.
  ///@notice We only emit this, so that an indexer can know that the order is completed and can thereby keep a correct context
  event MangroveOrderComplete();

  ///@notice Implements "Fill or kill" or "Good till cancelled" orders on a given offer list.
  ///@param tko the arguments in memory of the taker order
  ///@return res the result of the taker order. If `offerId==0`, no resting order was posted on `msg.sender`'s behalf.
  function take(TakerOrder memory tko) external payable returns (TakerOrderResult memory res);
}
