// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {IATokenIsh} from "mgv_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {LongKandel} from "./abstract/LongKandel.sol";
import {PushAndSupplyKandel} from "./abstract/PushAndSupplyKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract AaveKandel is PushAndSupplyKandel, LongKandel {
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param base Address of the base token of the market Kandel will act on
  ///@param quote Address of the quote token of the market Kandel will act on
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    PushAndSupplyKandel(mgv, base, quote, gasreq, gasprice, reserveId)
    LongKandel(base, quote)
  {}

  ///@notice Deposits funds to the contract's reserve
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds on the router (and supply on AAVE)
    pushAndSupplyRouter().pushAndSupply(BASE, baseAmount, QUOTE, quoteAmount, RESERVE_ID);
  }

  ///@notice withdraws base and quote from the contract's reserve
  ///@param baseAmount to withdraw (use uint(-1) for the whole balance)
  ///@param quoteAmount to withdraw (use uint(-1) for the whole balance)
  ///@param recipient the address to which the withdrawn funds should be sent to.
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) public override onlyAdmin {
    if (baseAmount != 0) {
      AavePooledRouter(address(pushAndSupplyRouter())).withdraw(BASE, RESERVE_ID, baseAmount);
    }
    if (quoteAmount != 0) {
      AavePooledRouter(address(pushAndSupplyRouter())).withdraw(QUOTE, RESERVE_ID, quoteAmount);
    }
    super.withdrawFunds(baseAmount, quoteAmount, recipient);
  }
}
