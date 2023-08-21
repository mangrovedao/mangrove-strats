// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePrivateRouter} from "mgv_src/strategies/routers/integrations/AavePrivateRouter.sol";
import {IATokenIsh} from "mgv_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {PushAndSupplyKandel} from "./abstract/PushAndSupplyKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat which posts offers on base/quote and quote/base offer lists with geometric price progression which stores funds on AAVE to generate yield.
contract ShortKandel is PushAndSupplyKandel {
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param base Address of the base token of the market Kandel will act on
  ///@param quote Address of the quote token of the market Kandel will act on
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    PushAndSupplyKandel(mgv, base, quote, gasreq, gasprice, reserveId)
  {}

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param token collateral type
  ///@param amount amount of collateral to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different ratio, pricePoints, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint firstAskIndex,
    Params calldata parameters,
    IERC20 token,
    uint amount
  ) external payable onlyAdmin {
    _deposit(token, amount);
    setParams(parameters);
    MGV.fund{value: msg.value}();
    _populateChunk(distribution, pivotIds, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice Deposits funds to the contract's reserve
  ///@param token the deposited asset
  ///@param amount to deposit
  function depositFunds(IERC20 token, uint amount) external onlyAdmin {
    _deposit(token, amount);
    pushAndSupplyRouter().pushAndSupply(token, amount, IERC20(address(0)), 0, RESERVE_ID);
  }

  ///@notice withdraws funds from the contract's reserve
  ///@param token the asset one wishes to withdraw
  ///@param amount to withdraw
  ///@param recipient the address to which the withdrawn funds should be sent to.
  function withdrawFunds(IERC20 token, uint amount, address recipient) external onlyAdmin {
    if (amount != 0) {
      router().pull(token, RESERVE_ID, amount, true);
    }
    _withdraw(token, amount, recipient);
  }
}
