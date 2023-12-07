// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

/// TakerOrderType is an enum that represents the type of a taker order.
/// @param GTC Good till cancelled enforces -> This order remains active until it is either filled or canceled by the trader.
/// * If an expiry date is set, This will be a GTD (Good till date) order.
/// * this will try a market order first, and if it is partially filled but the resting order fails to be posted, it won't revert the transaction.
/// @param GTCE Good till cancelled -> This order remains active until it is either filled or canceled by the trader. It doesn't have the restriction of avoiding immediate execution.
/// * If the resting order fails to be posted, it will revert the transaction.
/// @param PO Post only -> This order will not execute immediately against the market.
/// @param IOC Immediate or cancel -> This order must be filled immediately at the limit price or better. If the full order cannot be filled, the unfilled portion is canceled.
/// @param FOK Fill or kill -> This order must be filled in its entirety immediately at the limit price or better, or it is entirely canceled. There is no partial fulfillment.
enum TakerOrderType {
  GTC, // = 0
  GTCE, // = 1
  PO, // = 2
  IOC, // = 3
  FOK // = 4
}

using TakerOrderTypeLib for TakerOrderType global;

/// @title Library for TakerOrderType
/// @notice This library contains functions to check the compatibility of an order type with a resting or market order.
library TakerOrderTypeLib {
  /// @notice Returns true if the order type is compatible with a resting order.
  /// i.e. GTC, GTCE, PO
  /// @param orderType the order type
  /// @return postRestingOrder true if the order type is compatible with a resting order.
  function postRestingOrder(TakerOrderType orderType) internal pure returns (bool) {
    return uint8(orderType) < 3;
  }

  /// @notice Returns true if the order type can be posted as a resting order.
  /// @param orderType the order type
  /// @param filled true if the order is filled
  /// @return postRestingOrder true if the order type can be posted as a resting order.
  function postRestingOrder(TakerOrderType orderType, bool filled) internal pure returns (bool) {
    return !filled && orderType.postRestingOrder();
  }

  /// @notice Returns true if the order type is compatible with a market order.
  /// i.e. GTC, GTCE, IOC, FOK
  /// @param orderType the order type
  /// @return executesMarketOrder true if the order type is compatible with a market order.
  function executesMarketOrder(TakerOrderType orderType) internal pure returns (bool) {
    return orderType != TakerOrderType.PO;
  }

  /// @notice Returns true if the market order is successful according to the order type.
  /// @param orderType the order type
  /// @param filled true if the order is filled
  /// @return marketOrderSucceded true if the market order is successful according to the order type.
  function marketOrderSucceded(TakerOrderType orderType, bool filled) internal pure returns (bool) {
    // if post resting order is true, this means
    return filled || orderType.postRestingOrder() || orderType == TakerOrderType.IOC;
  }

  /// @notice Returns true if the market order should be executed.
  /// * This function returns false if the order type is PO (Post Only).
  /// @param orderType the order type
  /// @return shouldExecuteMarketOrder true if the market order should be executed.
  function shouldExecuteMarketOrder(TakerOrderType orderType) internal pure returns (bool) {
    return orderType != TakerOrderType.PO;
  }

  /// @notice Returns true if the order requires posting the resting order to be successful.
  /// i.e. GTCE (Good till cancelled enforced) and PO (Post Only)
  /// Reverting Post Only orders is not necessary but saves the gas of the taker.
  /// @param orderType the order type
  /// @return enforcePostRestingOrder true if the order requires posting the resting order to be successful.
  function enforcePostRestingOrder(TakerOrderType orderType) internal pure returns (bool) {
    return orderType == TakerOrderType.GTCE || orderType == TakerOrderType.PO;
  }
}
