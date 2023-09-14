// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AbstractRouter} from "../AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration, DataTypes} from "./AaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title Router for smart offers that borrow promised assets on AAVE
///@dev router assumes all bound makers share the same liquidity
///@dev if the same maker has many smart offers that are succeptible to be consumed in the same market order, it can set `BUFFER_SIZE` to a non zero value to increase gas efficiency (see below)

contract AavePrivateRouter is AaveMemoizer, AbstractRouter {
  ///@notice Logs unexpected throws from AAVE
  ///@param maker the address of the smart offer that called the router
  ///@param asset the type of asset involved in the interaction with the pool
  ///@param aaveReason the aave error string cast to a bytes32. Interpret the string by reading `src/strategies/vendor/aave/v3/Errors.sol`
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

  /// @notice portion of the outbound token credit line that is borrowed from the pool when this router calls the `borrow` function
  /// @notice expressed in percent of the total borrow capacity of this router
  /// @dev setting BUFFER_SIZE to 0 will make this router borrow only what is missing from the pool
  /// @dev setting BUFFER_SIZE to 100 will make this router borrow its whole credit line from the Pool. As a consequence this router's position can be liquidated on the next block should the router fail to repay its debt at the end of the taker's order. This could happen if the taker consummes an offer of its own during the m.o and manages to put the pool into a state where it refuses repaying (should only be possible if the reserve is paused or inactive).
  /// (so as not to call `borrow` multiple times if the router is to be called several times in the same market order)
  uint internal immutable BUFFER_SIZE;

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRate interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  ///@param overhead is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  ///@param buffer_size portion of the outbound token credit line that is borrowed from the pool when this router calls the `borrow`.
  ///@dev `msg.sender` will be admin of this router
  constructor(address addressesProvider, uint interestRate, uint overhead, uint buffer_size)
    AaveMemoizer(addressesProvider, interestRate)
    AbstractRouter(overhead)
  {
    require(buffer_size <= 100, "PrivateRouter/InvalidBufferSize");
    BUFFER_SIZE = buffer_size;
  }

  ///@notice Deposit funds on this router from the calling maker contract
  ///@dev no transfer to AAVE is done at this moment.
  ///@inheritdoc AbstractRouter
  function __push__(IERC20 token, address, uint amount) internal override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "AavePrivateRouter/pushFailed");
    return amount;
  }

  ///@notice Moves assets to pool. If asset has any debt it repays the debt before depositing the residual
  ///@param token the asset to push to the pool
  ///@param amount the amount of asset
  ///@param m the memoizer
  ///@param noRevert whether the function should revert with AAVE or return the revert message
  ///@return reason in case AAVE reverts (cast to a bytes32)
  function _toPool(IERC20 token, uint amount, Memoizer memory m, bool noRevert) internal returns (bytes32 reason) {
    if (amount == 0) {
      return bytes32(0);
    }
    if (debtBalanceOf(token, m) > 0) {
      uint repaid;
      (repaid, reason) = _repay(token, amount, address(this), noRevert);
      if (reason != bytes32(0)) {
        return reason;
      }
      amount -= repaid;
    }
    reason = _supply(token, amount, address(this), noRevert);
  }

  ///@notice deposits router-local balance of an asset on the AAVE pool
  ///@param token the address of the asset
  function flushBuffer(IERC20 token) external onlyBound {
    Memoizer memory m;
    _toPool(token, balanceOf(token, m), m, false);
  }

  ///@notice pushes each given token from the calling maker contract to this router, then supplies the whole router-local balance to AAVE
  ///@param token0 the first token to deposit
  ///@param amount0 the amount of `token0` to deposit
  ///@param token1 the second token to deposit, might by IERC20(address(0)) when making a single token deposit
  ///@param amount1 the amount of `token1` to deposit
  ///@dev an offer logic should call this instead of `flush` when it is the last posthook to be executed
  ///@dev this can be determined by checking during __lastLook__ whether the logic will trigger a withdraw from AAVE (this is the case if router's balance of token is empty)
  ///@dev this function is also to be used when user deposits funds on the maker contract
  ///@dev if repay/supply should fail, funds are left on the router's balance, therefore bound maker must implement a public withdraw function to recover these funds if needed
  function pushAndSupply(IERC20 token0, uint amount0, IERC20 token1, uint amount1) external onlyBound {
    require(TransferLib.transferTokenFrom(token0, msg.sender, address(this), amount0), "AavePrivateRouter/pushFailed");
    require(TransferLib.transferTokenFrom(token1, msg.sender, address(this), amount1), "AavePrivateRouter/pushFailed");
    Memoizer memory m0;
    Memoizer memory m1;

    bytes32 reason;
    if (address(token0) != address(0)) {
      reason = _toPool(token0, balanceOf(token0, m0), m0, true);
      if (reason != bytes32(0)) {
        emit LogAaveIncident(msg.sender, address(token0), reason);
      }
    }
    if (address(token1) != address(0)) {
      reason = _toPool(token1, balanceOf(token1, m1), m1, true);
      if (reason != bytes32(0)) {
        emit LogAaveIncident(msg.sender, address(token1), reason);
      }
    }
  }

  // structs to avoid stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  ///@notice queries the reserve data of a particular token on Aave
  ///@param token the asset reserve
  ///@return reserveData of the asset
  function reserveData(IERC20 token) external view returns (DataTypes.ReserveData memory) {
    Memoizer memory m;
    return reserveData(token, m);
  }

  ///@notice returns line of credit of `this` contract in the form of a pair (maxRedeem, maxBorrow) corresponding respectively
  ///to the max amount of `token` this contract can withdraw from the pool, and the max amount of `token` it can borrow in addition (after withdrawing `maxRedeem`)
  ///@param token the asset one wishes to get from the pool
  ///@param m the memoizer
  ///@param target if `maxRedeem < target` will try also borrowing. Otherwise `maxBorrow = 0`
  ///@return (maxRedeem, maxBorrow) capacity of `this` contract on the pool.
  function maxGettableUnderlying(IERC20 token, Memoizer memory m, uint target) internal view returns (uint, uint) {
    Underlying memory underlying; // asset parameters
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      /*liquidationBonus*/
      ,
      underlying.decimals,
      /*reserveFactor*/
      ,
      /*emode_category*/
    ) = ReserveConfiguration.getParams(reserveData(token, m).configuration);

    // redeemPower = account.liquidationThreshold * account.collateral - account.debt
    Account memory userAccountData = userAccountData(m);
    uint redeemPower =
      (userAccountData.liquidationThreshold * userAccountData.collateral - userAccountData.debt * 10 ** 4) / 10 ** 4;

    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())
    uint maxRedeemableUnderlying = (
      redeemPower // in 10**underlying.decimals
        * 10 ** underlying.decimals * 10 ** 4
    ) / (underlying.liquidationThreshold * assetPrice(token, m));

    maxRedeemableUnderlying =
      (maxRedeemableUnderlying < overlyingBalanceOf(token, m)) ? maxRedeemableUnderlying : overlyingBalanceOf(token, m);

    if (target <= maxRedeemableUnderlying) {
      return (maxRedeemableUnderlying, 0);
    }
    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = (maxRedeemableUnderlying * underlying.ltv) / 10 ** 4;

    uint borrowPowerInUnderlying = (userAccountData.borrowPower * 10 ** underlying.decimals) / assetPrice(token, m);

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    // max borrow power in underlying after max redeem has been withdrawn
    uint maxBorrowAfterRedeemInUnderlying = borrowPowerInUnderlying - borrowPowerImpactOfRedeemInUnderlying;

    return (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying);
  }

  ///@notice pulls tokens from the pool according to the following policy:
  /// * if this contract's balance already has `amount` tokens, then those tokens are transferred w/o calling the pool
  /// * otherwise, all tokens that can be withdrawn from this contract's account on the pool are withdrawn
  /// * if withdrawal is insufficient to match `amount` the missing tokens are borrowed.
  /// Note we do not borrow the full capacity as it would put this contract is a liquidatable state. A malicious offer in the same market order could prevent the posthook to repay the debt via a possible manipulation of the pool's state using flashloans.
  /// * if pull is `strict` then only amount is sent to the calling maker contract, otherwise the totality of pulled funds are sent to maker
  ///@inheritdoc AbstractRouter
  function __pull__(IERC20 token, address, uint amount, bool strict) internal override returns (uint pulled) {
    Memoizer memory m;
    // invariant `localBalance === token.balanceOf(this)`
    // `missing === max(0,localBalance - amount)`
    uint localBalance = balanceOf(token, m);
    uint missing = amount > localBalance ? amount - localBalance : 0;
    if (missing > 0) {
      // there is not enough on the router's balance to pay the taker
      // one needs to withdraw and/or borrow on the pool
      (uint maxWithdraw, uint maxBorrow) = maxGettableUnderlying(token, m, missing);
      // trying to withdraw if asset is available on pool
      if (maxWithdraw > 0) {
        uint withdrawBuffer = (BUFFER_SIZE * maxWithdraw) / 100;
        // withdrawing max(buffer,min(missing,maxWithdraw)`
        uint toWithdraw = withdrawBuffer > missing ? withdrawBuffer : (maxWithdraw > missing ? missing : maxWithdraw);
        (uint withdrawn, bytes32 reason) = _redeem(token, toWithdraw, address(this), true);
        if (reason == bytes32(0)) {
          // success
          localBalance += withdrawn;
          missing = localBalance > amount ? 0 : amount - localBalance;
        } else {
          // failed to withdraw possibly because asset is used as collateral for borrow or pool is dry
          emit LogAaveIncident(msg.sender, address(token), reason);
        }
      }
      // testing whether one still misses funds to pay the taker and if so, whether one can borrow what's missing
      if (missing > 0) {
        // because we might already have pulled some tokens from the pool, the code below reverts if anything goes wrong
        uint borrowBuffer = (BUFFER_SIZE * maxBorrow) / 100;
        // if buffer < missing, we still borrow missing from the pool in order not to make offer fail if possible
        uint toBorrow = borrowBuffer > missing ? borrowBuffer : missing;

        require(toBorrow <= maxBorrow, "AavePrivateRouter/NotEnoughFundsOnPool");
        // try to borrow and revert if Aave throws
        _borrow(token, toBorrow, address(this), false);
        localBalance += toBorrow;
      }
    }
    pulled = strict ? amount : localBalance;
    require(TransferLib.transferToken(token, msg.sender, pulled), "AavePrivateRouter/pullFailed");
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId) internal view override {
    // any reserveId passes the checklist since this router does not pull or push liquidity to it (but unknown reserveId will have 0 shares)
    reserveId;
    // we check that `token` is listed on AAVE
    require(checkAsset(token), "AavePooledRouter/tokenNotLendableOnAave");
    require( // required to supply or withdraw token on pool
    token.allowance(address(this), address(POOL)) > 0, "AavePooledRouter/hasNotApprovedPool");
  }

  ///@inheritdoc AbstractRouter
  function __activate__(IERC20 token) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  ///@notice revokes pool approval for a certain asset. This router will no longer be able to deposit on AAVE Pool
  ///@param token the address of the asset whose approval must be revoked.
  function revokeLenderApproval(IERC20 token) external onlyAdmin {
    _approveLender(token, 0);
  }

  ///@notice prevents AAVE from using a certain asset as collateral for lending
  ///@param token the asset address
  function exitMarket(IERC20 token) external onlyAdmin {
    _exitMarket(token);
  }

  ///@notice re-allows AAVE to use certain assets as collateral for lending
  ///@dev market is automatically entered at first deposit
  ///@param tokens the asset addresses
  function enterMarket(IERC20[] calldata tokens) external onlyAdmin {
    _enterMarkets(tokens);
  }

  ///@notice allows AAVE manager to claim the rewards attributed to this router by AAVE
  ///@param assets the list of overlyings (aToken, debtToken) whose rewards should be claimed
  ///@dev if some rewards are eligible they are sent to `aaveManager`
  ///@return rewardList the addresses of the claimed rewards
  ///@return claimedAmounts the amount of claimed rewards
  function claimRewards(address[] calldata assets)
    external
    onlyAdmin
    returns (address[] memory rewardList, uint[] memory claimedAmounts)
  {
    return _claimRewards(assets, msg.sender);
  }

  struct AssetBalances {
    uint local;
    uint onPool;
    uint debt;
    uint liquid;
    uint creditLine;
  }

  ///@notice returns important balances of a given asset
  ///@param token the asset whose balances are queried
  ///@return bal
  /// .local the balance of the asset on the router
  /// .onPool the amount of asset deposited on the pool
  /// .debt the amount of asset that has been borrowed. A good invariant to check is `debt > 0 <=> local == 0 && onPool == 0`
  /// .liquid is the amount of asset that can be withdrawn from the pool w/o incurring debt. Invariant is `liquid <= onPool`
  /// .creditLine is the amount of asset that can be borrowed from the pool when all `liquid` asset have been withdrawn.
  function assetBalances(IERC20 token) public view returns (AssetBalances memory bal) {
    Memoizer memory m;
    bal.debt = debtBalanceOf(token, m);
    bal.local = balanceOf(token, m);
    bal.onPool = overlyingBalanceOf(token, m);
    (bal.liquid, bal.creditLine) = maxGettableUnderlying(token, m, type(uint).max);
  }

  ///@notice view of user account data
  ///@return data of this router's account on AAVE
  ///@dev account liquidation is possible when `data.health < 10**18`
  function accountData() public view returns (Account memory data) {
    Memoizer memory m;
    return userAccountData(m);
  }

  ///@notice returns the amount of asset that this contract has, either locally or on pool
  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address) public view override returns (uint) {
    Memoizer memory m;
    return overlyingBalanceOf(token, m) + balanceOf(token, m);
  }

  ///@notice sets user Emode
  ///@param categoryId the Emode categoy (0 for none, 1 for stable...)
  function setEMode(uint8 categoryId) external onlyAdmin {
    POOL.setUserEMode(categoryId);
  }
}
