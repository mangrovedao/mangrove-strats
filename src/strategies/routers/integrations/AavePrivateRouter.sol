// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MonoRouter, AbstractRouter, ApprovalInfo} from "../abstract/MonoRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration, DataTypes} from "./AaveMemoizer.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

///@title Router for smart offers that borrow promised assets on AAVE
///@dev router assumes all bound makers share the same liquidity
///@dev upon pull, router sends local tokens first and then tries to borrow missing liquidity from the pool. It will not try to withdraw funds from the pool.

contract AavePrivateRouter is AaveMemoizer, MonoRouter {
  ///@notice Logs unexpected throws from AAVE
  ///@param maker the address of the smart offer that called the router
  ///@param asset the type of asset involved in the interaction with the pool
  ///@param aaveReason the aave error string cast to a bytes32. Interpret the string by reading `src/strategies/vendor/aave/v3/Errors.sol`
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRate interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  ///@param overhead is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  ///@dev `msg.sender` will be admin of this router
  constructor(address addressesProvider, uint interestRate, uint overhead)
    AaveMemoizer(addressesProvider, interestRate)
    MonoRouter(overhead)
  {}

  ///@notice Deposit funds on this router from the calling maker contract
  ///@dev no transfer to AAVE is done at this moment.
  ///@inheritdoc AbstractRouter
  function __push__(IERC20 token, address, uint amount) internal override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "AavePrivateRouter/pushFailed");
    Memoizer memory m;
    (uint repaid, bytes32 reason) = repayIfAnyDebt(token, amount, m, true);
    if (reason != bytes32(0)) {
      emit LogAaveIncident(msg.sender, address(token), reason);
    }
    return amount - repaid;
  }

  ///@notice push and supplies token on the pool, repaying any ongoing debt first
  ///@param token the asset one wishes to supply
  ///@param amount of available token from `msg.sender`
  function pushAndSupply(IERC20 token, uint amount) external onlyBound {
    uint pushed = __push__(token, address(this), amount);
    _supply(token, pushed, address(this), false);
  }

  ///@notice supplies local balance of tokens on the pool
  ///@param token the asset one wishes to supply
  function supply(IERC20 token) external onlyAdmin {
    _supply(token, token.balanceOf(address(this)), address(this), false);
  }

  ///@notice If asset has any debt it repays it and leaves any surplus on `this` balance
  ///@param token the asset to push to the pool
  ///@param amount the amount of asset
  ///@param m the memoizer
  ///@param noRevert whether the function should revert with AAVE or return the revert message
  ///@return repaid the fraction of amount that was used to repay debt
  ///@return reason in case AAVE reverts (cast to a bytes32)
  function repayIfAnyDebt(IERC20 token, uint amount, Memoizer memory m, bool noRevert)
    internal
    returns (uint repaid, bytes32 reason)
  {
    if (amount == 0) {
      return (0, bytes32(0));
    }
    if (debtBalanceOf(token, m, address(this)) > 0) {
      (repaid, reason) = _repay(token, amount, address(this), noRevert);
    }
    require(noRevert || reason == bytes32(0));
  }

  ///@notice queries the reserve data of a particular token on Aave
  ///@param token the asset reserve
  ///@return reserveData of the asset
  function reserveData(IERC20 token) external view returns (DataTypes.ReserveData memory) {
    Memoizer memory m;
    return reserveData(token, m);
  }

  ///@notice pulls tokens from the pool according to the following policy:
  /// * if this contract's balance already has `amount` tokens, then those tokens are transferred w/o calling the pool
  /// * otherwise, all tokens that can be withdrawn from this contract's account on the pool are withdrawn
  /// * if withdrawal is insufficient to match `amount` the missing tokens are borrowed.
  /// Note we do not borrow the full capacity as it would put this contract is a liquidatable state. A malicious offer in the same market order could prevent the posthook to repay the debt via a possible manipulation of the pool's state using flashloans.
  /// * if pull is `strict` then only amount is sent to the calling maker contract, otherwise the totality of pulled funds are sent to maker
  ///@inheritdoc AbstractRouter
  function __pull__(
    IERC20 token,
    address,
    uint amount,
    bool, /*always strict*/
    ApprovalInfo calldata /*standard erc20 approval*/
  ) internal override returns (uint pulled) {
    Memoizer memory m;
    // invariant `localBalance === token.balanceOf(this)`
    // `missing === max(0,localBalance - amount)`
    pulled = balanceOf(token, m, address(this));
    if (pulled < amount) {
      // we then try to borrow what's missing
      bytes32 reason = _borrow(token, amount - pulled, address(this), true);
      pulled += reason == bytes32(0) ? amount - pulled : pulled;
    }
    require(TransferLib.transferToken(token, msg.sender, pulled), "AavePrivateRouter/pullFailed");
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId, address) internal view override {
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
    bal.debt = debtBalanceOf(token, m, address(this));
    bal.local = balanceOf(token, m, address(this));
    bal.onPool = overlyingBalanceOf(token, m, address(this));
    (bal.liquid, bal.creditLine) = maxGettableUnderlying(token, m, address(this), type(uint).max);
  }

  ///@notice view of user account data
  ///@return data of this router's account on AAVE
  ///@dev account liquidation is possible when `data.health < 10**18`
  function accountData() public view returns (Account memory data) {
    Memoizer memory m;
    return userAccountData(m, address(this));
  }

  ///@notice returns the amount of asset that this contract has, either locally or on pool
  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address) public view override returns (uint) {
    Memoizer memory m;
    return overlyingBalanceOf(token, m, address(this)) + balanceOf(token, m, address(this));
  }

  ///@notice sets user Emode
  ///@param categoryId the Emode categoy (0 for none, 1 for stable...)
  function setEMode(uint8 categoryId) external onlyAdmin {
    POOL.setUserEMode(categoryId);
  }
}
