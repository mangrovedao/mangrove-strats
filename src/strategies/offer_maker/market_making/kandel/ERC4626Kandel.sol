// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/ERC4626Router.sol";
import {RoutingOrderLib as RL} from "@mgv-strats/src/strategies/routers/abstract/RoutingOrderLib.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {CoreKandel} from "./abstract/CoreKandel.sol";
import {IOfferLogic} from "@mgv-strats/src/strategies/interfaces/IOfferLogic.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

///@title A Kandel strat with geometric price progression which stores funds in ERC4626 vaults to generate yield.
contract ERC4626Kandel is GeometricKandel {
  ///@notice Indication that this is first puller (returned from __lastLook__) so posthook should deposit liquidity in vault
  bytes32 internal constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gas required by the strat to execute
  ///@param routerParams routing policy parameters for this contract
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, RouterParams memory routerParams)
    GeometricKandel(mgv, olKeyBaseQuote, routerParams)
  {
    setGasreq(gasreq);
    activate(BASE);
    activate(QUOTE);
  }

  ///@notice returns the router as an ERC4626 router
  ///@return The ERC4626 router.
  function erc4626Router() private view returns (ERC4626Router) {
    return ERC4626Router(address(router()));
  }

  ///@notice deposits funds to be available for being offered. Will increase `pending`.
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds to the router (and deposit in vault)
    if (baseAmount > 0) {
      erc4626Router().__push__(BASE, baseAmount);
    }
    if (quoteAmount > 0) {
      erc4626Router().__push__(QUOTE, quoteAmount);
    }
  }

  ///@inheritdoc CoreKandel
  ///@notice tries to withdraw funds on this contract's balance and then reaches out to the router available funds for the remainder
  function withdrawFundsForToken(IERC20 token, uint amount, address recipient) internal override {
    uint localBalance = token.balanceOf(address(this));

    // if amount is `type(uint).max` tell the router to withdraw all it can (i.e. pass `type(uint).max` to the router)
    // else withdraw only if there is not enough funds on this contract to match amount
    uint amount_ = amount == type(uint).max ? amount : localBalance > amount ? 0 : amount - localBalance;

    if (amount_ != 0) {
      erc4626Router().__pull__(token, amount_);
    }
    super.withdrawFundsForToken(token, amount, recipient);
  }

  ///@notice returns the amount of the router's that can be used by this contract, as well as local balance for the token offered for the offer type.
  ///@param ba the offer type.
  ///@return balance the balance of the token.
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    return erc4626Router().vaults[outboundOfOfferType(ba)].balanceOf(address(this)) + super.reserveBalance(ba);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds from vault
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return
      (IERC20(order.olKey.outbound_tkn).balanceOf(address(router())) < order.takerWants) ? IS_FIRST_PULLER : makerData;
  }

  ///@notice overrides and replaces Direct's posthook in order to push to vault with a single call when offer logic is the first to pull funds
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repostStatus)
  {
    // handle dual offer posting
    transportSuccessfulOrder(order);

    // handles pushing back liquidity to the router
    if (makerData == IS_FIRST_PULLER) {
      // if first puller, then router should deposit liquidity in vault
      uint baseBalance = BASE.balanceOf(address(this));
      uint quoteBalance = QUOTE.balanceOf(address(this));
      if (baseBalance > 0) {
        erc4626Router().__push__(BASE, baseBalance);
      }
      if (quoteBalance > 0) {
        erc4626Router().__push__(QUOTE, quoteBalance);
      }
      // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // reposting offer residual if any - call super to flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
  }
}
