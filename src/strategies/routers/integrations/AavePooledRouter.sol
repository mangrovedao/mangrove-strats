// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AbstractRouter, RL} from "../abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {HasAaveBalanceMemoizer, IPoolAddressesProvider} from "./HasAaveBalanceMemoizer.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

///@title Router acting as a liquidity reserve on AAVE for multiple depositors (possibly coming from different maker contracts).
///@notice maker contracts deposit/withdraw their user(s) fund(s) on this router, which maintains an accounting of shares attributed to each depositor
///@dev deposit is made via `pushAndSupply`, and withdraw is made via `pull` with `strict=true`.
///@dev this router ensures an optimal gas cost complexity when the following strategy is used:
/// * on the offer logic side:
///    * in `makerExecute`, check whether logic is the first caller to the router. This is done by checking whether the balance of outbound tokens of the router is below the required amount. If so the logic should return a special bytes32 (say `"firstCaller"`) to makerPosthook.
///    * in `__put__`  the logic stores incoming liquidity on the strat balance
///    * in `__get__` the logic pulls liquidity from the router in a non strict manner
///    * in __posthookSuccess|Fallback__ the logic pushes both inbound and outbound tokens to the router. If message from makerExecute is `"firstCaller"`, the logic additionally asks the router to supply all its outbound and inbound tokens to AAVE. This can be done is a single step by calling `pushAndSupply`
/// * on the router side:
///    * `__pull__`  checks whether local balance of token is below required amount. If so it pulls all its funds from AAVE (this includes funds that do not belong to the owner of the calling contract) and sends to caller all the owner's reserve (according to the shares attributed to the owner - except in case of liquidity sharing where only requested amount is transferred). This router then decreases owner's shares accordingly. (note that if AAVE has no liquidity crisis, then the owner's shares will be temporarily 0)
///    * `__push__` transfers the requested amount of tokens from the calling maker contract and increases owner's shares, but does not supply on AAVE

contract AavePooledRouter is HasAaveBalanceMemoizer, AbstractRouter {
  ///@notice the manager which controls which pools are allowed.
  address public aaveManager;

  ///@notice The `aaveManager` has been set.
  ///@param manager the new manager.
  ///@notice By emitting this data, an indexer will be able to keep track of what manager is used.
  event SetAaveManager(address manager);

  ///@notice An error occurred during deposit to AAVE.
  ///@param token the deposited token. This is indexed so that RPC calls can filter on it.
  ///@param maker the maker contract that was calling `pushAndSupply`. This is indexed so that RPC calls can filter on it.
  ///@param reserveId the reserve identifier that was calling `pushAndSupply`. This is indexed so that RPC calls can filter on it.
  ///@param aaveReason the reason from AAVE.
  ///@notice By emitting this data, an indexer will be able to keep track of what incidents that has happened.
  event AaveIncident(IERC20 indexed token, address indexed maker, address indexed reserveId, bytes32 aaveReason);

  ///@notice the total shares for each token, i.e. the total shares one would need to possess in order to claim the entire pool of tokens.
  mapping(IERC20 => uint) internal _totalShares;

  ///@notice the number of shares for a reserve for a token, i.e. the shares of this router that are attributed to a particular reserve.
  mapping(IERC20 => mapping(address => uint)) internal _sharesOf;

  ///@notice offset for initial shares to be minted
  ///@dev this amount must be big enough to avoid minting 0 shares via "donation"
  /// see https://github.com/code-423n4/2022-09-y2k-finance-findings/issues/449
  /// mitigation proposed here: https://ethereum-magicians.org/t/address-eip-4626-inflation-attacks-with-virtual-shares-and-assets/12677

  uint public constant OFFSET = 19;
  ///@notice initial shares to be minted
  uint internal constant INIT_MINT = 10 ** OFFSET;

  /// OVERFLOW analysis w.r.t offset choice:
  /// worst case is:
  /// 1. Alice, the first minter deposits 1 wei. She gets `10**OFFSET` shares for this.
  /// 2. Alice deposits `amount` into the pool. She gets `10**OFFSET * amount / (amount + 1)` additional shares.
  /// 3. Alice computes her balance. Total shares of the pool is the total share of Alice  ~ `amount * 10**OFFSET` and the pool has ~ `amount` tokens
  ///  so Alice's balance is ~ `(amount * amount * 10**OFFSET) / 10**OFFSET * amount`. This overflows if `amount * amount * 10**OFFSET` overflows.
  ///  Suppose that amount is `2**x`. One must verify that x + x + log2(10) * OFFSET < 256
  ///  This imposes x < (256 - log2(10) * OFFSET) / 2
  /// with OFFSET = 19 we get x < 101 so no overflow is guaranteed for a user balance that can hold on a `uint96`.

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  constructor(IPoolAddressesProvider addressesProvider) HasAaveBalanceMemoizer(addressesProvider) AbstractRouter() {
    setAaveManager(msg.sender);
  }

  ///@notice returns the shares of this router that are attributed to a particular reserve
  ///@param token the address of the asset
  ///@param reserveId the reserve identifier
  ///@return shares the amount of shares attributed to `reserveId`.
  ///@dev `sharesOf(token,id)/totalShares(token)` represent the portion of this contract's balance of `token`s that the `reserveId` can claim
  function sharesOf(IERC20 token, address reserveId) public view returns (uint shares) {
    shares = _sharesOf[token][reserveId];
  }

  ///@notice returns the total shares one would need to possess in order to claim the entire pool of tokens
  ///@param token the address of the asset
  ///@return total the total amount of shares
  function totalShares(IERC20 token) public view returns (uint total) {
    total = _totalShares[token];
  }

  ///@notice theoretically available funds to this router either in overlying or in tokens (part of it may not be redeemable from AAVE)
  ///@param token the asset whose balance is required
  ///@return balance of the asset
  ///@dev this function relies on the AAVE promise that aToken are in one-to-one correspondence with claimable underlying and use the same decimals
  function totalBalance(IERC20 token) external view returns (uint balance) {
    BalanceMemoizer memory memoizer;
    return _totalBalance(token, memoizer);
  }

  ///@notice `totalBalance` with memoization of balance queries
  ///@param token the asset whose balance is required
  ///@param memoizer the memoizer
  ///@return balance of the asset
  function _totalBalance(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint balance) {
    balance = balanceOf(token, memoizer) + balanceOfOverlying(token, memoizer);
  }

  ///@inheritdoc AbstractRouter
  function tokenBalanceOf(RL.RoutingOrder calldata routingOrder) public view override returns (uint) {
    BalanceMemoizer memory memoizer;
    return _balanceOfReserve(routingOrder.token, routingOrder.fundOwner, memoizer);
  }

  ///@notice `balanceOfReserve` with memoization of balance queries
  ///@param token the asset one wants to know the balance of
  ///@param reserveId the identifier of the reserve whose balance is queried
  ///@return balance available funds for the reserve
  ///@param memoizer the memoizer
  function _balanceOfReserve(IERC20 token, address reserveId, BalanceMemoizer memory memoizer)
    internal
    view
    returns (uint balance)
  {
    uint totalShares_ = totalShares(token);
    balance = totalShares_ == 0 ? 0 : sharesOf(token, reserveId) * _totalBalance(token, memoizer) / totalShares_;
  }

  ///@notice computes how many shares an amount of tokens represents
  ///@param token the address of the asset
  ///@param amount of tokens
  ///@param memoizer the memoizer
  ///@return shares the shares that correspond to amount
  function _sharesOfAmount(IERC20 token, uint amount, BalanceMemoizer memory memoizer)
    internal
    view
    returns (uint shares)
  {
    uint totalShares_ = totalShares(token);
    shares = totalShares_ == 0 ? INIT_MINT : totalShares_ * amount / _totalBalance(token, memoizer);
  }

  ///@notice mints a certain quantity of shares for a given asset and assigns them to a reserve
  ///@param token the address of the asset
  ///@param reserveId the address of the reserve who will be assigned new shares
  ///@param amount the amount of assets added to the reserve
  ///@param memoizer the memoizer
  function _mintShares(IERC20 token, address reserveId, uint amount, BalanceMemoizer memory memoizer) internal {
    // computing how many shares should be minted for reserve
    uint sharesToMint = _sharesOfAmount(token, amount, memoizer);
    _sharesOf[token][reserveId] += sharesToMint;
    _totalShares[token] += sharesToMint;
  }

  ///@notice burns a certain quantity of reserve's shares for a given asset
  ///@param token the address of the asset
  ///@param reserveId the address of the reserve who will have shares burnt
  ///@param amount the amount of assets withdrawn from reserve
  ///@param memoizer the memoizer
  ///@dev if one is trying to burn shares from a pool that doesn't have any, the call to `_sharesOfAmount` will return `INIT_MINT`
  ///@dev and thus this contract will throw with "AavePooledRouter/insufficientFunds", even if one is trying to burn 0 shares.
  function _burnShares(IERC20 token, address reserveId, uint amount, BalanceMemoizer memory memoizer) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToBurn = _sharesOfAmount(token, amount, memoizer);
    uint ownerShares = _sharesOf[token][reserveId];
    require(sharesToBurn <= ownerShares, "AavePooledRouter/insufficientFunds");
    // no underflow due to require above
    _sharesOf[token][reserveId] = ownerShares - sharesToBurn;
    // no underflow since _totalShares is the sum of all shares including ownerShares, and the above require.
    _totalShares[token] -= sharesToBurn;
  }

  ///@notice Deposit funds on this router from the calling maker contract
  ///@dev no transfer to AAVE is done at that moment.
  ///@dev data must encode an address for reserveId.
  ///@inheritdoc AbstractRouter
  function __push__(RL.RoutingOrder memory routingOrder, uint amount) internal override returns (uint) {
    BalanceMemoizer memory memoizer;
    _mintShares(routingOrder.token, routingOrder.fundOwner, amount, memoizer);
    // Transfer must occur *after* state updating _mintShares above
    require(
      TransferLib.transferTokenFrom(routingOrder.token, msg.sender, address(this), amount),
      "AavePooledRouter/pushFailed"
    );
    return amount;
  }

  ///@notice deposit router-local balance of an asset on the AAVE pool
  ///@param token the address of the asset
  ///@param noRevert does not revert if supplies throws
  ///@return reason for revert from Aave.
  function flushBuffer(IERC20 token, bool noRevert) public boundOrAdmin returns (bytes32 reason) {
    uint amount = token.balanceOf(address(this));
    _approveLender(token, amount);
    return _supply(token, amount, address(this), noRevert);
  }

  ///@notice pushes given tokens from the calling maker contract to this router, then supplies the whole router-local balance to AAVE
  ///@param token asset to be pushed to this contract
  ///@param amount the amount of token to be pushed from maker contract to this router
  ///@param fundOwner share owner
  ///@return pushed tokens to this contract
  function _pushAndSupply(IERC20 token, uint amount, address fundOwner) internal returns (uint pushed) {
    if (amount > 0) {
      pushed = __push__(RL.createOrder({fundOwner: fundOwner, token: token}), amount);
    }
    bytes32 aaveData = flushBuffer(token, true);
    if (aaveData != bytes32(0)) {
      emit AaveIncident(token, msg.sender, fundOwner, aaveData);
    }
  }

  ///@notice pushes each given token from the calling maker contract to this router, then supplies the whole router-local balance to AAVE
  ///@param token0 the first token to deposit
  ///@param amount0 the amount of `token0` to deposit
  ///@param token1 the second token to deposit
  ///@param amount1 the amount of `token1` to deposit
  ///@param fundOwner the reserve whose shares should be increased
  ///@return pushed0 the amount of token0 that were successfully pushed
  ///@return pushed1 the amount of token1 that were successfully pushed
  ///@dev an offer logic should call this instead of `flush` when it is the last posthook to be executed
  ///@dev this can be determined by checking during __lastLook__ whether the logic will trigger a withdraw from AAVE (this is the case if router's balance of token is empty)
  ///@dev this call be performed even for tokens with 0 amount for the offer logic, since the logic can be the first in a chain and router needs to flush all
  ///@dev this function is also to be used when user deposits funds on the maker contract
  function pushAndSupply(IERC20 token0, uint amount0, IERC20 token1, uint amount1, address fundOwner)
    external
    onlyBound
    returns (uint pushed0, uint pushed1)
  {
    // Push will fail for amount of 0, but since this function is only called for the first maker contract in a chain
    // it needs to also flush tokens with a contract-local 0 amount.
    // token[0/1] can be address(0) if using this function for only one token
    if (address(token0) != address(0)) {
      pushed0 = _pushAndSupply(token0, amount0, fundOwner);
    }
    if (address(token1) != address(0)) {
      pushed1 = _pushAndSupply(token1, amount1, fundOwner);
    }
  }

  ///@inheritdoc AbstractRouter
  ///@dev outside a market order (i.e if `__pull__` is not called during offer logic's execution) the `token` balance of this router should be empty.
  /// This may not be the case when a "donation" occurred to this contract or if the maker posthook failed to push funds back to AAVE
  /// If the donation is large enough to cover the pull request we use the donation funds
  function __pull__(RL.RoutingOrder memory routingOrder, uint amount, bool strict) internal override returns (uint) {
    // The amount to redeem from AAVE
    uint toRedeem;
    // The amount to transfer to the calling maker contract
    uint amount_;
    BalanceMemoizer memory memoizer;
    // The local buffer of token to transfer in case funds have already been redeemed or due to a donation.
    uint buffer = balanceOf(routingOrder.token, memoizer);
    uint reserveBalance = _balanceOfReserve(routingOrder.token, routingOrder.fundOwner, memoizer);
    if (buffer < amount) {
      // this pull is the first of the market order (that requires funds from AAVE) so we redeem all the reserve from AAVE
      // note in theory we should check buffer == 0 but donation may have occurred.
      // This check forces donation to be at least the amount of outbound tokens promised by caller to avoid griefing (depositing a small donation to make offer fail).
      toRedeem = balanceOfOverlying(routingOrder.token, memoizer);
      amount_ = strict ? amount : reserveBalance;
    } else {
      // since buffer >= amount, this call is not the first pull of the market order (unless a big donation occurred) and we do not withdraw from AAVE
      // we take all we can from the buffer (possibly less than amount_ computed above)
      // toRedeem = 0
      amount_ = strict ? amount : (buffer > reserveBalance ? reserveBalance : buffer);
    }
    if (amount_ == 0) {
      // redeemAndTransfer would try to burn 0 shares and revert
      return 0;
    } else {
      redeemAndTransfer(routingOrder.token, routingOrder.fundOwner, amount_, toRedeem, memoizer);
      return amount_;
    }
  }

  ///@notice redeems some funds from AAVE pool and transfer some amount to msg.sender.
  ///@param token the asset to transfer
  ///@param reserveId the shares on which funds are being drawn
  ///@param amountToTransfer final amount of asset to transfer
  ///@param amountToRedeem funds that need to be pulled from AAVE for final transfer to succeed
  ///@param memoizer the memoizer
  function redeemAndTransfer(
    IERC20 token,
    address reserveId,
    uint amountToTransfer,
    uint amountToRedeem,
    BalanceMemoizer memory memoizer
  ) internal {
    _burnShares(token, reserveId, amountToTransfer, memoizer);
    // redeem does not change amount of shares. We do this after burning to avoid redeeming on AAVE if caller doesn't have the required funds.
    if (amountToRedeem > 0) {
      // this call will throw if AAVE has a liquidity crisis
      _redeem(token, amountToRedeem, address(this), false);
    }
    // Transferring funds to the maker contract, at this point we must revert if things go wrong because shares have been burnt on the premise that `amount_` will be transferred.
    require(TransferLib.transferToken(token, msg.sender, amountToTransfer), "AavePooledRouter/withdrawFailed");
  }

  ///@notice withdraw funds from the pool on behalf of some reserve id
  ///@param token the asset to withdraw
  ///@param reserveId the identifier of the share holder
  ///@param amount the amount to withdraw. Use type(uint).max to require withdrawal of the total balance of the caller
  function withdraw(IERC20 token, address reserveId, uint amount) external onlyBound {
    BalanceMemoizer memory memoizer;
    if (amount == type(uint).max) {
      amount = _balanceOfReserve(token, reserveId, memoizer);
    }
    uint buffer = balanceOf(token, memoizer);
    uint toRedeem = buffer > amount ? 0 : amount - buffer;
    redeemAndTransfer(token, reserveId, amount, toRedeem, memoizer);
  }

  ///@notice prevents AAVE from using a certain asset as collateral for lending
  ///@param token the asset address
  function exitMarket(IERC20 token) external onlyCaller(aaveManager) {
    _exitMarket(token);
  }

  ///@notice re-allows AAVE to use certain assets as collateral for lending
  ///@dev market is automatically entered at first deposit
  ///@param tokens the asset addresses
  function enterMarket(IERC20[] calldata tokens) external onlyCaller(aaveManager) {
    _enterMarkets(tokens);
  }

  ///@notice allows AAVE manager to claim the rewards attributed to this router by AAVE
  ///@param assets the list of overlyings (aToken, debtToken) whose rewards should be claimed
  ///@dev if some rewards are eligible they are sent to `aaveManager`
  ///@return rewardList the addresses of the claimed rewards
  ///@return claimedAmounts the amount of claimed rewards
  function claimRewards(address[] calldata assets)
    external
    onlyCaller(aaveManager)
    returns (address[] memory rewardList, uint[] memory claimedAmounts)
  {
    return _claimRewards(assets, msg.sender);
  }

  ///@notice sets a new AAVE manager
  ///@param aaveManager_ the new address of the AAVE manager
  ///@dev if any reward is active for pure lenders, `aaveManager` will be able to claim them
  function setAaveManager(address aaveManager_) public {
    require(msg.sender == admin() || msg.sender == aaveManager, "AccessControlled/Invalid");
    require(aaveManager_ != address(0), "AavePooledReserve/0xAaveManager");
    aaveManager = aaveManager_;
    emit SetAaveManager(aaveManager_);
  }
}
