// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_strat_src/strategies/MangroveOffer.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_strat_src/strategies/routers/integrations/AavePooledRouter.sol";
import {IATokenIsh} from "mgv_strat_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {CoreKandel} from "./abstract/CoreKandel.sol";
import {ICoreKandel} from "./abstract/ICoreKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract AaveKandel is GeometricKandel {
  ///@notice Indication that this is first puller (returned from __lastLook__) so posthook should deposit liquidity on AAVE
  bytes32 internal constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound base and inbound quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gasreq to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, address reserveId)
    GeometricKandel(mgv, olKeyBaseQuote, gasreq, reserveId)
  {
    // one makes sure it is not possible to deploy an AAVE kandel on aTokens
    // allowing Kandel to deposit aUSDC for instance would conflict with other Kandel instances bound to the same router
    // and trading on USDC.
    // The code in isOverlying verifies that neither base nor quote are official AAVE overlyings.
    require(
      !isOverlying(olKeyBaseQuote.outbound) && !isOverlying(olKeyBaseQuote.inbound), "AaveKandel/cannotTradeAToken"
    );
  }

  /// @notice Verifies that token is not an official AAVE overlying.
  /// @param token the token to verify.
  /// @return true if overlying; otherwise, false.
  function isOverlying(address token) internal view returns (bool) {
    try IATokenIsh(token).UNDERLYING_ASSET_ADDRESS() returns (address) {
      return true;
    } catch {}
    return false;
  }

  ///@notice Sets the AaveRouter as router and activates router for base and quote
  ///@param router_ the Aave router to use.
  function initialize(AavePooledRouter router_) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`. We call __activate__ instead of activate just to save gas.
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(offerGasreq());
  }

  ///@inheritdoc ICoreKandel
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds on the router (and supply on AAVE)
    AavePooledRouter(address(router())).pushAndSupply(BASE, baseAmount, QUOTE, quoteAmount, RESERVE_ID);
  }

  ///@inheritdoc CoreKandel
  function withdrawFundsForToken(IERC20 token, uint amount, address recipient) internal override {
    if (amount != 0) {
      AavePooledRouter(address(router())).withdraw(token, RESERVE_ID, amount);
    }
    super.withdrawFundsForToken(token, amount, recipient);
  }

  ///@notice returns the amount of the router's balance that belong to this contract for the token offered for the offer type.
  ///@inheritdoc ICoreKandel
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return AavePooledRouter(address(router())).balanceOfReserve(token, RESERVE_ID) + super.reserveBalance(ba);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return (IERC20(order.olKey.outbound).balanceOf(address(router())) < order.takerWants) ? IS_FIRST_PULLER : makerData;
  }

  ///@notice overrides and replaces Direct's posthook in order to push and supply on AAVE with a single call when offer logic is the first to pull funds from AAVE
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
      // if first puller, then router should deposit liquidity on AAVE
      AavePooledRouter(address(router())).pushAndSupply(
        BASE, BASE.balanceOf(address(this)), QUOTE, QUOTE.balanceOf(address(this)), RESERVE_ID
      );
      // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // reposting offer residual if any - call super to flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
  }
}
