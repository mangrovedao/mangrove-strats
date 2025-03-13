// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MockERC4626, IERC20} from "@mgv-strats/test/lib/mocks/MockERC4626.sol";
import {
  ERC4626Kandel,
  ERC4626Router,
  IERC20 as KandelToken
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626Kandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";

contract ERC4626KandelTest is CoreKandelTest {
  ERC4626Router router;
  ERC4626Kandel erc4626Kandel;
  // Mock ERC4626 vaults for testing
  IERC4626 baseVault;
  IERC4626 quoteVault;

  TestToken randomToken;
  IERC4626 randomVault;

  receive() external payable {}

  function __setForkEnvironment__() internal override {
    super.__setForkEnvironment__();
    randomToken = new TestToken($(this), "RandomToken", "RT", 18);
    randomVault = IERC4626(address(new MockERC4626(IERC20(address(randomToken)), "Random Vault", "vRANDOM")));
  }

  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    // Deploy mock ERC4626 vaults for base and quote tokens
    baseVault = IERC4626(address(new MockERC4626(IERC20(address(base)), "Base Vault", "vBASE")));
    quoteVault = IERC4626(address(new MockERC4626(IERC20(address(quote)), "Quote Vault", "vQUOTE")));
    uint kandel_gasreq = 800_000;
    router = new ERC4626Router();
    router.setVaultForToken(base, baseVault, 0);
    router.setVaultForToken(quote, quoteVault, 0);
    erc4626Kandel = new ERC4626Kandel(
      mgv, olKey, kandel_gasreq, Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: true})
    );

    router.bind(address(erc4626Kandel));
    erc4626Kandel.setAdmin(deployer);
    router.setAdmin(address(erc4626Kandel));

    // Give approval for kandel to pull tokens
    base.approve(address(erc4626Kandel), type(uint).max);
    quote.approve(address(erc4626Kandel), type(uint).max);

    // Assume tokens behave normally
    base.transferResponse(TestToken.MethodResponse.Normal);
    quote.approveResponse(TestToken.MethodResponse.Normal);

    return erc4626Kandel;
  }

  function test_setup() public {
    assertEq(address(erc4626Kandel.router()), address(router), "Router not set correctly");
    assertTrue(router.isBound(address(erc4626Kandel)), "Kandel not bound to router");
    assertEq(router.admin(), address(erc4626Kandel), "Router admin not set correctly");
  }

  function test_deposit_funds() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6; // 1000 USDC

    uint baseShares = baseVault.previewDeposit(baseAmount);
    uint quoteShares = quoteVault.previewDeposit(quoteAmount);

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    uint baseSharesBefore = baseVault.balanceOf(address(router));
    uint quoteSharesBefore = quoteVault.balanceOf(address(router));

    erc4626Kandel.depositFunds(baseAmount, quoteAmount);

    assertEq(base.balanceOf(address(router)), 0, "Base not deposited correctly");
    assertEq(quote.balanceOf(address(router)), 0, "Quote not deposited correctly");

    assertEq(baseVault.balanceOf(address(router)) - baseSharesBefore, baseShares, "Base shares not deposited correctly");
    assertEq(
      quoteVault.balanceOf(address(router)) - quoteSharesBefore, quoteShares, "Quote shares not deposited correctly"
    );
  }

  function test_withdraw_funds() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    erc4626Kandel.depositFunds(baseAmount, quoteAmount);
    vm.prank(maker);
    erc4626Kandel.withdrawFunds(baseAmount, quoteAmount, address(this));

    assertEq(base.balanceOf(address(this)), baseAmount, "Base not withdrawn correctly");
    assertEq(quote.balanceOf(address(this)), quoteAmount, "Quote not withdrawn correctly");
  }

  function test_admin_withdraw_tokens() public {
    uint tokenAmount = 10 ether;
    deal($(randomToken), address(router), tokenAmount);
    uint makerBalanceBefore = randomToken.balanceOf(address(this));
    vm.prank(maker);
    erc4626Kandel.adminWithdrawTokens(KandelToken(address(randomToken)), tokenAmount, address(this));
    uint makerBalanceAfter = randomToken.balanceOf(address(this));
    assertEq(makerBalanceAfter - makerBalanceBefore, tokenAmount);
  }

  function test_admin_withdraw_native() public {
    uint etherAmount = 10 ether;
    deal(address(router), etherAmount);
    uint makerBalanceBefore = address(this).balance;
    vm.prank(maker);
    erc4626Kandel.adminWithdrawNative(etherAmount, address(this));
    uint makerBalanceAfter = address(this).balance;
    assertEq(makerBalanceAfter - makerBalanceBefore, etherAmount);
  }

  function test_set_vault_for_token() public virtual {
    vm.prank(address(maker));
    erc4626Kandel.setVaultForToken(randomToken, randomVault, 0);
    assertEq((address(router.vaults(randomToken))), address(randomVault));
  }

  function test_reserve_balance() public {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    uint baseReservesBefore = erc4626Kandel.reserveBalance(Ask);
    uint quoteReservesBefore = erc4626Kandel.reserveBalance(Bid);

    erc4626Kandel.depositFunds(baseAmount, quoteAmount);

    assertEq(erc4626Kandel.reserveBalance(Ask) - baseReservesBefore, baseAmount, "Incorrect base reserve change");
    assertEq(erc4626Kandel.reserveBalance(Bid) - quoteReservesBefore, quoteAmount, "Incorrect quote reserve change");
  }

  function test_strats_with_same_admin_but_different_id_do_not_share_liquidity(uint16 baseAmount, uint16 quoteAmount)
    public
  {
    deal($(base), maker, baseAmount);
    deal($(quote), maker, quoteAmount);
    GeometricKandel kdl_ = __deployKandel__(maker, address(0), true);
    assertTrue(kdl_.FUND_OWNER() != kdl.FUND_OWNER(), "Strats should not have the same reserveId");
    vm.prank(maker);
    kdl.depositFunds(baseAmount, quoteAmount);

    assertEq(kdl_.reserveBalance(Ask), 0, "funds should not be shared");
    assertEq(kdl_.reserveBalance(Bid), 0, "funds should not be shared");
  }

  function test_revert_set_vault_for_token_with_high_slippage() public virtual {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    erc4626Kandel.depositFunds(baseAmount, quoteAmount);

    MockERC4626 newBaseVault = new MockERC4626(IERC20(address(base)), "some vault", "sm");
    uint minAssetsOut = 5 ether;

    vm.expectRevert("ERC4626Router/insufficientAssets");
    vm.prank(address(maker));
    erc4626Kandel.setVaultForToken(base, newBaseVault, minAssetsOut);
  }

  fallback() external {}
}
