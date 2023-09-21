// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";

///@title Core external functions and events for Kandel strats.
interface ICoreKandel {
  ///@notice the gasprice has been set.
  ///@param value the gasprice for offers.
  ///@notice By emitting this data, an indexer will be able to keep track of what gasprice is used.
  event SetGasprice(uint value);

  ///@notice the gasreq has been set.
  ///@param value the gasreq (including router's gasreq) for offers
  ///@notice By emitting this data, an indexer will be able to keep track of what gasreq is used.
  event SetGasreq(uint value);

  ///@notice the step size has been set.
  ///@param value the step size in amount of price points to jump for posting dual offer
  event SetStepSize(uint value);

  ///@notice the Kandel instance is credited of `amount` by its owner.
  ///@param token the asset. This is indexed so that RPC calls can filter on it.
  ///@param amount the amount.
  ///@notice By emitting this data, an indexer will be able to keep track of what credits are made.
  event Credit(IERC20 indexed token, uint amount);

  ///@notice the Kandel instance is debited of `amount` by its owner.
  ///@param token the asset. This is indexed so that RPC calls can filter on it.
  ///@param amount the amount.
  ///@notice By emitting this data, an indexer will be able to keep track of what debits are made.
  event Debit(IERC20 indexed token, uint amount);

  ///@notice the amount of liquidity that is available for the strat but not offered by the given offer type.
  ///@param ba the offer type.
  ///@return the amount of pending liquidity. Will be negative if more is offered than is available on the reserve balance.
  ///@dev Pending could be withdrawn or invested by increasing offered volume.
  function pending(OfferType ba) external view returns (int);

  ///@notice the total balance available for the strat of the offered token for the given offer type.
  ///@param ba the offer type.
  ///@return balance the balance of the token.
  function reserveBalance(OfferType ba) external view returns (uint balance);

  ///@notice deposits funds to be available for being offered. Will increase `pending`.
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) external;

  ///@notice withdraws the amounts of the given tokens to the recipient.
  ///@param baseAmount the amount of base tokens to withdraw.
  ///@param quoteAmount the amount of quote tokens to withdraw.
  ///@param recipient the recipient of the funds.
  ///@dev it is up to the caller to make sure there are still enough funds for live offers.
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) external;

  ///@notice sets the gasprice for offers
  ///@param gasprice the gasprice.
  function setGasprice(uint gasprice) external;

  ///@notice sets the gasreq (including router's gasreq) for offers
  ///@param gasreq the gasreq.
  function setGasreq(uint gasreq) external;

  ///@notice sets the step size
  ///@param stepSize the step size.
  function setStepSize(uint stepSize) external;
}
