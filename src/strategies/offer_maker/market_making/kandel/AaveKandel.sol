// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {AavePooledRouter} from "@mgv-strats/src/strategies/routers/integrations/AavePooledRouter.sol";
import {IAToken} from "@mgv-strats/src/strategies/vendor/aave/v3/contracts/interfaces/IAToken.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {CoreKandel} from "./abstract/CoreKandel.sol";
import {IOfferLogic} from "@mgv-strats/src/strategies/interfaces/IOfferLogic.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract AaveKandel is GeometricKandel {
  ///@notice Indication that this is first puller (returned from __lastLook__) so posthook should deposit liquidity on AAVE
  bytes32 internal constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, address reserveId)
    GeometricKandel(mgv, olKeyBaseQuote, reserveId)
  {
    // one makes sure it is not possible to deploy an AAVE kandel on aTokens
    // allowing Kandel to deposit aUSDC for instance would conflict with other Kandel instances bound to the same router
    // and trading on USDC.
    // The code in isOverlying verifies that neither base nor quote are official AAVE overlyings.
    require(
      !isOverlying(olKeyBaseQuote.outbound_tkn) && !isOverlying(olKeyBaseQuote.inbound_tkn),
      "AaveKandel/cannotTradeAToken"
    );
  }

  /// @notice Verifies that token is not an official AAVE overlying.
  /// @param token the token to verify.
  /// @return true if overlying; otherwise, false.
  function isOverlying(address token) internal view returns (bool) {
    try IAToken(token).UNDERLYING_ASSET_ADDRESS() returns (address) {
      return true;
    } catch {}
    return false;
  }

  ///@notice returns the router as an Aave router
  ///@return The aave router.
  function pooledRouter() private view returns (AavePooledRouter) {
    return AavePooledRouter(address(router()));
  }

  ///@notice Sets the AaveRouter as router and activates router for base and quote
  ///@param router_ the Aave router to use.
  ///@param gasreq the gas required to execute an offer of this Kandel strat
  function initialize(AavePooledRouter router_, uint gasreq) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`. We call __activate__ instead of activate just to save gas.
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(gasreq);
  }

  /// @inheritdoc IOfferLogic
  function setRouter(AbstractRouter router) public virtual override {
    require(router != NO_ROUTER, "AaveKandel/noRouter");
    super.setRouter(router);
  }

  ///@notice deposits funds to be available for being offered. Will increase `pending`.
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds on the router (and supply on AAVE)
    pooledRouter().pushAndSupply(BASE, baseAmount, QUOTE, quoteAmount, RESERVE_ID);
  }

  ///@inheritdoc CoreKandel
  ///@notice tries to withdraw funds on this contract's balance and then reaches out to the router available funds for the remainder
  function withdrawFundsForToken(IERC20 token, uint amount, address recipient) internal override {
    uint localBalance = token.balanceOf(address(this));

    // if amount is `type(uint).max` tell the router to withdraw all it can (i.e. pass `type(uint).max` to the router)
    // else withdraw only if there is not enough funds on this contract to match amount
    uint amount_ = amount == type(uint).max ? amount : localBalance > amount ? 0 : amount - localBalance;

    if (amount_ != 0) {
      pooledRouter().withdraw(token, RESERVE_ID, amount_);
    }
    super.withdrawFundsForToken(token, amount, recipient);
  }

  ///@notice returns the amount of the router's that can be used by this contract, as well as local balance for the token offered for the offer type.
  ///@param ba the offer type.
  ///@return balance the balance of the token.
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return pooledRouter().balanceOfReserve(token, RESERVE_ID) + super.reserveBalance(ba);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return
      (IERC20(order.olKey.outbound_tkn).balanceOf(address(router())) < order.takerWants) ? IS_FIRST_PULLER : makerData;
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
      pooledRouter().pushAndSupply(
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
