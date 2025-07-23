// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {CompoundV2Router, ICToken} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {RoutingOrderLib as RL} from "@mgv-strats/src/strategies/routers/abstract/RoutingOrderLib.sol";
import {GeometricKandel} from "../abstract/GeometricKandel.sol";
import {CoreKandel} from "../abstract/CoreKandel.sol";
import {OfferType} from "../abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title A Kandel strat with geometric price progression which stores funds in Compound V2 markets to generate yield.
/// @notice This contract allows market making while earning lending yield on unused capital through Compound V2
contract CompoundKandel is GeometricKandel {
  /// @notice Constructor
  /// @param mgv The Mangrove deployment.
  /// @param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  /// @param gasreq the gas required by the strat to execute
  /// @param routerParams routing policy parameters for this contract
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, RouterParams memory routerParams)
    GeometricKandel(mgv, olKeyBaseQuote, routerParams)
  {
    setGasreq(gasreq);
    activate(BASE);
    activate(QUOTE);
  }

  /// @notice Returns the router as a Compound V2 router
  /// @return The CompoundV2Router instance
  function compoundRouter() private view returns (CompoundV2Router) {
    return CompoundV2Router(address(router()));
  }

  /// @notice Deposits funds to the contract's reserve
  /// @param baseAmount the amount of base tokens to deposit.
  /// @param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    compoundRouter().pushAndDeposit(BASE, baseAmount, QUOTE, quoteAmount);
  }

  /// @inheritdoc CoreKandel
  function withdrawFundsForToken(IERC20 token, uint amount, address recipient) internal override {
    uint localBalance = token.balanceOf(address(this));
    uint totalReserveBalance = reserveBalance(offerTypeOfOutbound(token));

    if (amount == type(uint).max) {
      amount = totalReserveBalance;
    }

    // if amount is `type(uint).max` tell the router to withdraw all it can (i.e. pass `type(uint).max` to the router)
    // else withdraw only if there is not enough funds on this contract to match amount
    uint amount_ = amount < localBalance ? 0 : amount - localBalance;

    if (amount_ != 0) {
      amount_ = compoundRouter().withdraw(token, amount_);
    }
    super.withdrawFundsForToken(token, amount, recipient);
  }

  /// @notice Allows the admin to withdraw any tokens (and native) that is not the underlying ERC20 or cToken of the strat.
  /// @param token The token to withdraw.
  /// @param amount The amount of tokens to withdraw.
  /// @param recipient The recipient of the tokens.
  function adminWithdrawTokens(IERC20 token, uint amount, address recipient) public onlyAdmin {
    compoundRouter().adminWithdrawTokens(BASE, QUOTE, token, amount, recipient);
  }

  /// @notice Allows the admin to withdraw native tokens.
  /// @param amount The amount of native tokens to withdraw.
  /// @param recipient The recipient of the native tokens.
  function adminWithdrawNative(uint amount, address recipient) public onlyAdmin {
    compoundRouter().adminWithdrawNative(amount, recipient);
  }

  /// @notice Sets the Compound market for a given token.
  /// @param cToken The cToken market to set for the underlying token
  /// @dev Only callable by admin. Will withdraw all assets from old market if one exists, then deposit into new market
  function setMarket(ICToken cToken) public onlyAdmin {
    compoundRouter().setMarket(cToken);
  }

  /// @notice Returns the current cToken market addresses for the base and quote tokens
  /// @return baseMarket The address of the cToken market for the base token
  /// @return quoteMarket The address of the cToken market for the quote token
  function currentMarkets() public view returns (address baseMarket, address quoteMarket) {
    CompoundV2Router router = compoundRouter();
    baseMarket = address(router.markets(BASE));
    quoteMarket = address(router.markets(QUOTE));
  }

  /// @notice returns the amount of the router's that can be used by this contract, as well as local balance for the token offered for the offer type.
  /// @param ba the offer type.
  /// @return balance the balance of the token.
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    return compoundRouter().tokenBalanceOf(RL.createOrder({token: outboundOfOfferType(ba), fundOwner: address(this)}))
      + super.reserveBalance(ba);
  }

  /// @notice overrides and replaces Direct's posthook in order to push to Compound markets with a single call when offer logic is the first to pull funds
  /// @inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repostStatus)
  {
    // handle dual offer posting
    transportSuccessfulOrder(order);

    // if first puller, then router should deposit liquidity in Compound markets
    uint baseBalance = BASE.balanceOf(address(this));
    uint quoteBalance = QUOTE.balanceOf(address(this));

    compoundRouter().pushAndDeposit(BASE, baseBalance, QUOTE, quoteBalance);
    // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
    repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
  }
}
