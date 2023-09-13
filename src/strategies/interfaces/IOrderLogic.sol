// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, OLKey} from "mgv_src/MgvLib.sol";

///@title Interface for resting orders functionality.
interface IOrderLogic {
  ///@notice Information for creating a market order with a GTC or FOK semantics.
  ///@param olKey the offer list key.
  ///@param fillOrKill true to revert if market order cannot be filled and resting order failed or is not enabled; otherwise, false
  ///@param logPrice the price
  ///@param fillVolume the volume to fill
  ///@param fillWants if true (buying), the market order stops when `fillVolume` units of `olKey.outbound` have been obtained (fee included); otherwise (selling), the market order stops when `fillVolume` units of `olKey.inbound` have been sold.
  ///@param restingOrder whether the complement of the partial fill (if any) should be posted as a resting limit order.
  ///@param expiryDate timestamp (expressed in seconds since unix epoch) beyond which the order is no longer valid, 0 means forever
  ///@param offerId the id of an existing, dead offer owned by the taker to re-use for the resting order, 0 means no re-use.
  struct TakerOrder {
    OLKey olKey;
    bool fillOrKill;
    int logPrice;
    uint fillVolume;
    bool fillWants;
    bool restingOrder;
    uint expiryDate;
    uint offerId;
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
  }

  ///@notice Information about the order.
  ///@param mangrove The Mangrove contract on which the offer was posted
  ///@param olKeyHash the hash of the offer list key.
  ///@param taker The address of the taker
  ///@param fillOrKill The fillOrKill that take was called with
  ///@param logPrice The price
  ///@param fillVolume the volume to fill
  ///@param fillWants if true (buying), the market order stops when `fillVolume` units of `olKey.outbound` have been obtained (fee included); otherwise (selling), the market order stops when `fillVolume` units of `olKey.inbound` have been sold.
  ///@param restingOrder The restingOrder boolean take was called with
  ///@param expiryDate The expiry date take was called with
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param bounty How much bounty was given
  ///@param fee How much fee was paid for the order
  ///@param restingOrderId If a restingOrder was posted, then this holds the offerId for the restingOrder
  event OrderSummary(
    IMangrove mangrove,
    bytes32 indexed olKeyHash,
    address indexed taker,
    bool fillOrKill,
    int logPrice,
    uint fillVolume,
    bool fillWants,
    bool restingOrder,
    uint expiryDate,
    uint takerGot,
    uint takerGave,
    uint bounty,
    uint fee,
    uint restingOrderId
  );

  ///@notice Timestamp beyond which the given `offerId` should renege on trade.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The id of the offer to query for expiry for.
  ///@return res The timestamp beyond which `offerId` on the `olKey` offer list should renege on trade. 0 means no expiry.
  function expiring(bytes32 olKeyHash, uint offerId) external returns (uint);

  ///@notice Updates the expiry date for a specific offer.
  ///@param olKeyHash the hash of the offer list key.
  ///@param offerId The offer id whose expiry date is to be set.
  ///@param date in seconds since unix epoch
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  function setExpiry(bytes32 olKeyHash, uint offerId, uint date) external;

  ///@notice Implements "Fill or kill" or "Good till cancelled" orders on a given offer list.
  ///@param tko the arguments in memory of the taker order
  ///@return res the result of the taker order. If `offerId==0`, no resting order was posted on `msg.sender`'s behalf.
  function take(TakerOrder memory tko) external payable returns (TakerOrderResult memory res);
}
