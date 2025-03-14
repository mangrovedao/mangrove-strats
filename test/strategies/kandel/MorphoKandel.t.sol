// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626Kandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/ERC4626Kandel.sol";
import {
  MorphoVaultRouter,
  IMorphoRewardDistributor,
  IERC20 as RouterToken
} from "@mgv-strats/src/strategies/routers/integrations/MorphoVaultRouter.sol";
import {IMorphoFactory} from "@mgv-strats/src/strategies/interfaces/IMorphoFactory.sol";
import {ERC4626KandelTest} from "./ERC4626Kandel.t.sol";
import {MockMorphoFactory} from "test/lib/mocks/MockMorphoFactory.sol"; // Importing the MockMorphoFactory
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {MockERC4626, IERC20 as VaultToken} from "@mgv-strats/test/lib/mocks/MockERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";

contract MorphoKandelTest is ERC4626KandelTest {
  MorphoVaultRouter morphoRouter;
  MockMorphoFactory morphoFactory;

  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    // Deploy mock ERC4626 vaults for base and quote tokens
    baseVault = IERC4626(address(new MockERC4626(VaultToken(address(base)), "Base Vault", "vBASE")));
    quoteVault = IERC4626(address(new MockERC4626(VaultToken(address(quote)), "Quote Vault", "vQUOTE")));
    uint kandel_gasreq = 800_000;

    morphoFactory = new MockMorphoFactory();
    // Set both vaults as true in the mock factory
    morphoFactory.setVault(address(baseVault), true);
    morphoFactory.setVault(address(quoteVault), true);

    // Deploy Morpho router
    morphoRouter = new MorphoVaultRouter(IMorphoFactory(address(morphoFactory)), IMorphoRewardDistributor(address(1)));
    router = morphoRouter;

    router.setVaultForToken(base, baseVault, 0, 0);
    router.setVaultForToken(quote, quoteVault, 0, 0);
    erc4626Kandel = new ERC4626Kandel(
      mgv, olKey, kandel_gasreq, Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: true})
    );
    morphoRouter.bind(address(erc4626Kandel));
    erc4626Kandel.setAdmin(deployer);
    morphoRouter.setAdmin(address(erc4626Kandel));

    // Give approval for kandel to pull tokens
    base.approve(address(erc4626Kandel), type(uint).max);
    quote.approve(address(erc4626Kandel), type(uint).max);

    // Assume tokens behave normally
    base.transferResponse(TestToken.MethodResponse.Normal);
    quote.approveResponse(TestToken.MethodResponse.Normal);

    return erc4626Kandel;
  }

  function test_revert_on_non_morpho_vault() public {
    address nonMorphoVault = makeAddr("nonMorphoVault");
    // Should revert when trying to set a non-Morpho vault
    vm.prank(address(erc4626Kandel));
    vm.expectRevert("MorphoRouter/notMorpho");
    morphoRouter.setVaultForToken(RouterToken(address(base)), IERC4626(nonMorphoVault), 0, 0);
  }

  function test_success_on_morpho_vault() public {
    address morphoVault = makeAddr("morphoVault");
    morphoFactory.setVault(morphoVault, true);
    vm.prank(address(erc4626Kandel));
    morphoRouter.setVaultForToken(RouterToken(address(base)), IERC4626(morphoVault), 0, 0);
    assertEq(address(morphoRouter.vaults(RouterToken(address(base)))), morphoVault);
  }

  function test_set_vault_for_token() public override {
    morphoFactory.setVault(address(randomVault), true);
    super.test_set_vault_for_token();
  }

  function test_revert_set_vault_for_token_with_high_slippage() public override {
    uint baseAmount = 1 ether;
    uint quoteAmount = 1000 * 10 ** 6;

    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);

    erc4626Kandel.depositFunds(baseAmount, quoteAmount);

    MockERC4626 newBaseVault = new MockERC4626(VaultToken(address(base)), "some vault", "sm");
    morphoFactory.setVault(address(newBaseVault), true);

    uint minAssetsOut = 5 ether;

    vm.expectRevert("ERC4626Router/insufficientAssets");
    vm.prank(address(maker));
    erc4626Kandel.setVaultForToken(base, newBaseVault, minAssetsOut, 0);
  }
}
