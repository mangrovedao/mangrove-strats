// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MangroveOffer} from "@mgv-strats/src/strategies/MangroveOffer.sol";
import {MgvLib, OLKey} from "@mgv/src/core/MgvLib.sol";
import {ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/ERC4626Router.sol";
import {RoutingOrderLib as RL} from "@mgv-strats/src/strategies/routers/abstract/RoutingOrderLib.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {CoreKandel} from "./abstract/CoreKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

///@title A Kandel strat with geometric price progression which stores funds in ERC4626 vaults to generate yield.
///@notice NOTE: Nested vaults (vaults that deposit into other vaults) are not supported.
contract ERC4626Kandel is GeometricKandel {
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

  ///@notice Deposits funds to the contract's reserve
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    erc4626Router().pushAndDeposit(BASE, baseAmount, QUOTE, quoteAmount);
  }

  ///@inheritdoc CoreKandel
  function withdrawFundsForToken(IERC20 token, uint amount, address recipient) internal override {
    uint localBalance = token.balanceOf(address(this));
    uint reserveBalance = reserveBalance(offerTypeOfOutbound(token));

    if (amount == type(uint).max) {
      amount = reserveBalance;
    }

    // if amount is `type(uint).max` tell the router to withdraw all it can (i.e. pass `type(uint).max` to the router)
    // else withdraw only if there is not enough funds on this contract to match amount
    uint amount_ = amount < localBalance ? 0 : amount - localBalance;

    if (amount_ != 0) {
      amount_ = erc4626Router().withdraw(token, amount_);
    }
    super.withdrawFundsForToken(token, amount, recipient);
  }

  ///@notice Allows the admin to withdraw any tokens (and native) that is not the underlying ERC20 or ERC4626 of the strat.
  ///@param token The token to withdraw.
  ///@param amount The amount of tokens to withdraw.
  ///@param recipient The recipient of the tokens.
  function adminWithdrawTokens(IERC20 token, uint amount, address recipient) public onlyAdmin {
    erc4626Router().adminWithdrawTokens(BASE, QUOTE, token, amount, recipient);
  }

  ///@notice Allows the admin to withdraw native tokens.
  ///@param amount The amount of native tokens to withdraw.
  ///@param recipient The recipient of the native tokens.
  function adminWithdrawNative(uint amount, address recipient) public onlyAdmin {
    erc4626Router().adminWithdrawNative(amount, recipient);
  }

  ///@notice Sets the vault for a given token.
  ///@param token The token for which to set the vault
  ///@param vault The address of the vault to set
  ///@param minAssetsOut The minimum amount of assets that must be returned when withdrawing from the old vault
  ///@param minSharesOut The minimum amount of shares that must be returned when depositing into the new vault
  ///@dev Only callable by admin. Will withdraw all assets from old vault if one exists, then deposit into new vault
  function setVaultForToken(IERC20 token, IERC4626 vault, uint minAssetsOut, uint minSharesOut) public onlyAdmin {
    erc4626Router().setVaultForToken(token, vault, minAssetsOut, minSharesOut);
  }

  ///@notice Returns the current vault addresses for the base and quote tokens
  ///@return baseVault The address of the vault for the base token
  ///@return quoteVault The address of the vault for the quote token
  function currentVaults() public view returns (address baseVault, address quoteVault) {
    ERC4626Router router = erc4626Router();
    baseVault = address(router.vaults(BASE));
    quoteVault = address(router.vaults(QUOTE));
  }

  ///@notice returns the amount of the router's that can be used by this contract, as well as local balance for the token offered for the offer type.
  ///@param ba the offer type.
  ///@return balance the balance of the token.
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    return erc4626Router().tokenBalanceOf(RL.createOrder({token: outboundOfOfferType(ba), fundOwner: address(this)}))
      + super.reserveBalance(ba);
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

    // if first puller, then router should deposit liquidity in vault
    uint baseBalance = BASE.balanceOf(address(this));
    uint quoteBalance = QUOTE.balanceOf(address(this));

    erc4626Router().pushAndDeposit(BASE, baseBalance, QUOTE, quoteBalance);
    // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
    repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
  }
}
