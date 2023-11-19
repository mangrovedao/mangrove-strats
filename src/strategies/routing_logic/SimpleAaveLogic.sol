pragma solidity ^0.8.20;

import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {AaveMemoizer} from "@mgv-strats/src/strategies/integrations/AaveMemoizer.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

/// @title SimpleAaveLogic
/// @notice Routing logic for Aave wihtout credit line
contract SimpleAaveLogic is AbstractRouter, AaveMemoizer {
  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode) AaveMemoizer(addressesProvider, interestRateMode) {}

  ///@inheritdoc AbstractRouter
  function __pull__(RL.RoutingOrder memory routingOrder, bool strict) internal virtual override returns (uint) {
    Memoizer memory m;

    uint amount = strict ? routingOrder.amount : overlyingBalanceOf(routingOrder.token, m, routingOrder.fundOwner);

    if (amount == 0) {
      return 0;
    }

    require(
      TransferLib.transferTokenFrom(routingOrder.token, routingOrder.fundOwner, msg.sender, amount),
      "SimpleAaveLogic/TransferFailed"
    );

    uint redeemed = _redeem(routingOrder.token, amount, msg.sender);
    return redeemed;
  }

  ///@inheritdoc AbstractRouter
  function __push__(RL.RoutingOrder memory routingOrder) internal virtual override returns (uint pushed) {
    // just in time approval of the POOL in order to be able to deposit funds
    _approveLender(routingOrder.token, routingOrder.amount);
    _supply(routingOrder.token, routingOrder.amount, routingOrder.fundOwner, false);
    return routingOrder.amount;
  }

  ///@inheritdoc AbstractRouter
  function balanceOfReserve(RL.RoutingOrder calldata routingOrder) public view virtual override returns (uint balance) {
    Memoizer memory m;
    balance = overlyingBalanceOf(routingOrder.token, m, routingOrder.fundOwner);
  }
}
