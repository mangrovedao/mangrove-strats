// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {ApprovalInfo, ApprovalType} from "mgv_strat_src/strategies/utils/ApprovalTransferLib.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {Permit2Helpers} from "mgv_strat_test/lib/permit2/permit2Helpers.sol";
import {console} from "forge-std/console.sol";

contract SimpleEOARouterTest is OfferLogicTest, Permit2Helpers {
  SimpleRouter router;

  uint48 NONCE = 0;
  bytes32 DOMAIN_SEPARATOR;
  uint48 EXPIRATION;
  uint160 AMOUNT = 25;
  uint eoaPrivateKey;
  address eoaAddress;

  function setupLiquidityRouting() internal override {
    // OfferMaker has no router, replacing 0x router by a SimpleRouter
    router = new SimpleRouter();
    router.bind(address(makerContract));
    // maker must approve router
    vm.prank(deployer);
    makerContract.setRouter(router);

    vm.startPrank(owner);
    weth.approve(address(router), type(uint).max);
    usdc.approve(address(router), type(uint).max);
    vm.stopPrank();

    eoaPrivateKey = 0x12341234;
    eoaAddress = vm.addr(eoaPrivateKey);
    DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

    deal($(weth), eoaAddress, 1 ether);
    deal($(usdc), eoaAddress, cash(usdc, 2000));
    vm.prank(eoaAddress);
    weth.approve(address(permit2), type(uint).max);
    EXPIRATION = uint48(block.timestamp + 1000);
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  event MakerBind(address indexed maker);
  event MakerUnbind(address indexed maker);

  function test_admin_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    router.unbind(address(makerContract));
  }

  function test_maker_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    vm.prank(address(makerContract));
    router.unbind();
  }

  function test_pull_with_normal_approval() public {
    router.bind(address(this));

    ApprovalInfo memory approvalInfo;

    approvalInfo.approvalType = ApprovalType.NormalTransfer;

    uint startBalanceFrom = weth.balanceOf(eoaAddress);
    uint startBalanceTo = weth.balanceOf(address(this));

    vm.prank(eoaAddress);
    weth.approve(address(router), type(uint).max);

    router.pull(weth, eoaAddress, AMOUNT, true, approvalInfo);

    assertEq(weth.balanceOf(eoaAddress), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);
  }

  function test_pull_with_signature_transfer() public {
    router.bind(address(this));
    ApprovalInfo memory approvalInfo;

    approvalInfo.approvalType = ApprovalType.Permit2TransferOneTime;

    approvalInfo.permit2 = permit2;
    approvalInfo.permitTransferFrom = getPermitTransferFrom(address(weth), AMOUNT, NONCE, EXPIRATION);

    approvalInfo.signature = getPermitTransferSignatureWithSpecifiedAddress(
      approvalInfo.permitTransferFrom, eoaPrivateKey, DOMAIN_SEPARATOR, address(router)
    );

    uint startBalanceFrom = weth.balanceOf(eoaAddress);
    uint startBalanceTo = weth.balanceOf(address(this));

    router.pull(weth, eoaAddress, AMOUNT, true, approvalInfo);

    assertEq(weth.balanceOf(eoaAddress), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);
  }

  function test_pull_with_permit() public {
    router.bind(address(this));

    ApprovalInfo memory approvalInfo;

    approvalInfo.approvalType = ApprovalType.Permit2Transfer;

    approvalInfo.permit2 = permit2;
    approvalInfo.permit = getPermit(address(weth), AMOUNT * 3, EXPIRATION, NONCE, address(router));

    approvalInfo.signature = getPermitSignature(approvalInfo.permit, eoaPrivateKey, DOMAIN_SEPARATOR);

    uint startBalanceFrom = weth.balanceOf(eoaAddress);
    uint startBalanceTo = weth.balanceOf(address(this));

    router.pull(weth, eoaAddress, AMOUNT, true, approvalInfo);

    assertEq(weth.balanceOf(eoaAddress), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);

    approvalInfo.permit.spender = address(0);
    router.pull(weth, eoaAddress, AMOUNT, true, approvalInfo);

    assertEq(weth.balanceOf(eoaAddress), startBalanceFrom - AMOUNT * 2);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT * 2);

    vm.prank(eoaAddress);
    permit2.approve(address(weth), address(router), 0, EXPIRATION);

    uint amount = router.pull(weth, eoaAddress, AMOUNT, true, approvalInfo);

    assertEq(amount, 0);
  }
}
