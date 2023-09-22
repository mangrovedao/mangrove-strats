// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {StratTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "mgv_strat_test/lib/StratTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Permit2Router} from "mgv_strat_src/strategies/routers/Permit2Router.sol";
import {MangroveOrder} from "mgv_strat_src/strategies/MangroveOrder.sol";
import {MangroveOrderWithPermit2 as MangroveOrderWithPermit2} from
  "mgv_strat_src/strategies/MangroveOrderWithPermit2.sol";
import {SimpleRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IOrderLogic} from "mgv_strat_src/strategies/interfaces/IOrderLogic.sol";
import {SimpleRouter} from "mgv_strat_src/strategies/routers/SimpleRouter.sol";
import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "lib/permit2/test/utils/DeployPermit2.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {Permit2Helpers} from "mgv_strat_test/lib/permit2/permit2Helpers.sol";

contract MangroveWithPermit2Order_Test is StratTest, DeployPermit2, Permit2Helpers {
  uint constant GASREQ = 35_000;

  bytes32 DOMAIN_SEPARATOR;
  uint48 EXPIRATION;
  uint48 NONCE;

  uint constant MID_PRICE = 2200e18;
  // to check ERC20 logging

  event Transfer(address indexed from, address indexed to, uint value);

  event Permit(
    address indexed owner,
    address indexed token,
    address indexed spender,
    uint160 amount,
    uint48 expiration,
    uint48 nonce
  );

  event OrderSummary(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    address indexed taker,
    bool fillOrKill,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    bool restingOrder,
    uint expiryDate,
    uint takerGot,
    uint takerGave,
    uint bounty,
    uint fee,
    uint restingOrderId
  );

  IPermit2 internal permit2;
  MangroveOrder internal mgo;
  MangroveOrderWithPermit2 internal mgoWithPermit2;
  TestMaker internal ask_maker;
  TestMaker internal bid_maker;

  TestTaker internal sell_taker;
  PinnedPolygonFork internal fork;

  IOrderLogic.TakerOrderResult internal cold_buyResult;
  IOrderLogic.TakerOrderResult internal cold_sellResult;

  receive() external payable {}

  function takerWants(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return order.takerWants;
  }

  function takerGives(IOrderLogic.TakerOrder memory order) internal pure returns (uint) {
    return order.takerGives;
  }

  function setUp() public override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("DAI"));
    setupMarket(base, quote);

    permit2 = IPermit2(deployPermit2());
    DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();
    EXPIRATION = uint48(block.timestamp + 1000);
    NONCE = 0;
    // this contract is admin of MangroveOrder and its router
    mgo = new MangroveOrder(IMangrove(payable(mgv)), $(this), GASREQ);
    mgoWithPermit2 = new MangroveOrderWithPermit2(IMangrove(payable(mgv)), IPermit2(permit2), $(this), GASREQ);
    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    mgo.activate(tokens);
    mgoWithPermit2.activate(tokens);

    // `this` contract will act as `MangroveOrder` user
    deal($(base), $(this), 10 ether);
    deal($(quote), $(this), 10_000 ether);

    TransferLib.approveToken(base, address(mgo.router()), 10 ether);
    TransferLib.approveToken(quote, address(mgo.router()), 10_000 ether);

    // user approves `mgo` to pull quote or base when doing a market order
    TransferLib.approveToken(base, address(permit2), 10 ether);
    TransferLib.approveToken(quote, address(permit2), 10_000 ether);

    permit2.approve(address(base), address(mgoWithPermit2.router()), type(uint160).max, type(uint48).max);
    permit2.approve(address(quote), address(mgoWithPermit2.router()), type(uint160).max, type(uint48).max);

    // `sell_taker` will take resting bid
    sell_taker = setupTaker($(quote), $(base), "sell-taker");
    deal($(base), $(sell_taker), 10 ether);

    // if seller wants to sell directly on mangrove
    vm.prank($(sell_taker));
    TransferLib.approveToken(base, $(mgv), 10 ether);
    // if seller wants to sell via mgo
    vm.prank($(sell_taker));
    TransferLib.approveToken(quote, $(mgv), 10 ether);

    // populating order book with offers
    ask_maker = setupMaker($(base), $(quote), "ask-maker");
    vm.deal($(ask_maker), 10 ether);

    bid_maker = setupMaker($(quote), $(base), "bid-maker");
    vm.deal($(bid_maker), 10 ether);

    deal($(base), $(ask_maker), 10 ether);
    deal($(quote), $(bid_maker), 10000 ether);

    // pre populating book with cold maker offers.
    ask_maker.approveMgv(base, 10 ether);
    uint gives = 1 ether;
    ask_maker.newOfferWithFunding( /*wants quote*/ quoteFromBase(MID_PRICE, gives), gives, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(quoteFromBase(MID_PRICE + 1e18, gives), gives, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(quoteFromBase(MID_PRICE + 2e18, gives), gives, 50_000, 0, 0, 0.1 ether);

    bid_maker.approveMgv(quote, 10000 ether);
    uint wants = 1 ether;
    bid_maker.newOfferWithFunding(wants, quoteFromBase(MID_PRICE - 10e18, wants), 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding(wants, quoteFromBase(MID_PRICE - 11e18, wants), 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding( /*wants base*/
      wants, /*gives quote*/ quoteFromBase(MID_PRICE - 12e18, wants), 50_000, 0, 0, 0.1 ether
    );

    IOrderLogic.TakerOrder memory buyOrder;
    IOrderLogic.TakerOrder memory sellOrder;
    // depositing a cold MangroveOrder offer.
    buyOrder = createBuyOrderEvenLowerPriceAndLowerVolume();
    buyOrder.restingOrder = true;
    buyOrder.expiryDate = block.timestamp + 1;

    sellOrder = createSellOrderEvenLowerPriceAndLowerVolume();
    sellOrder.restingOrder = true;
    sellOrder.expiryDate = block.timestamp + 1;

    cold_buyResult = mgo.take{value: 0.1 ether}(buyOrder);
    cold_sellResult = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(cold_buyResult.offerId * cold_sellResult.offerId > 0, "Resting offer failed to be published on mangrove");
    // mgo ask
    // 4 ┆ 1999 DAI  /  1 WETH 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker asks
    // 1 ┆ 2000 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 2 ┆ 2001 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 3 ┆ 2002 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // ------------------------------------------------------------------
    // mgo bid
    // 4 ┆ 1 WETH  /  1991 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker bids
    // 1 ┆ 1 WETH  /  1990 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 2 ┆ 1 WETH  /  1989 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 3 ┆ 1 WETH  /  1988 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
  }

  function __freshTaker__(uint balBase, uint balQuote, address fresh_taker) internal {
    deal($(quote), fresh_taker, balQuote);
    deal($(base), fresh_taker, balBase);
    deal(fresh_taker, 1 ether);

    vm.startPrank(fresh_taker);
    // always unlimitted approval permit2
    quote.approve(address(permit2), type(uint).max);
    base.approve(address(permit2), type(uint).max);
    vm.stopPrank();
  }

  function freshTaker(uint balBase, uint balQuote) internal returns (address fresh_taker) {
    fresh_taker = freshAddress("MangroveOrderTester");
    __freshTaker__(balBase, balQuote, fresh_taker);
    // allow router to pull funds from permit2
    vm.startPrank(fresh_taker);
    TransferLib.approveToken(base, address(mgo.router()), type(uint160).max);
    TransferLib.approveToken(quote, address(mgo.router()), type(uint160).max);
    vm.stopPrank();
  }

  function freshTakerForPermit2(uint balBase, uint balQuote, uint privKey) internal returns (address fresh_taker) {
    fresh_taker = vm.addr(privKey);
    __freshTaker__(balBase, balQuote, fresh_taker);
  }

  ////////////////////////
  /// Tests taker side ///
  ////////////////////////

  function quoteFromBase(uint price_e18, uint outboundAmt) internal pure returns (uint) {
    return price_e18 * outboundAmt / 1e18;
  }

  function outboundFromInbound(uint price_e18, uint inboundAmt) internal pure returns (uint) {
    return inboundAmt * 1e18 / price_e18;
  }

  function createBuyOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: fillVolume,
      takerGives: quoteFromBase(MID_PRICE - 1e18, fillVolume),
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
  }

  /// At half the volume, but same price
  function createBuyOrderHalfVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createBuyOrder();
    order.takerWants = fillVolume;
    order.takerGives = quoteFromBase(MID_PRICE - 1e18, fillVolume);
  }

  function createBuyOrderHigherPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createBuyOrder();
    // A high price so as to take ask_maker's offers
    order.takerWants = fillVolume;
    order.takerGives = quoteFromBase(MID_PRICE + 10000e18, fillVolume);
  }

  /// At lower price, same volume
  function createBuyOrderLowerPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createBuyOrder();
    order.takerWants = fillVolume;
    order.takerGives = quoteFromBase(MID_PRICE - 2e18, fillVolume);
  }

  function createBuyOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createBuyOrder();
    order.takerWants = fillVolume;
    order.takerGives = quoteFromBase(MID_PRICE - 9e18, fillVolume);
  }

  function createSellOrder() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: quoteFromBase(MID_PRICE - 9e18, fillVolume),
      takerGives: fillVolume,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
  }

  function createSellOrderLowerPrice() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 2 ether;
    order = createSellOrder();
    order.takerWants = quoteFromBase(MID_PRICE - 8e18, fillVolume);
    order.takerGives = fillVolume;
  }

  function createSellOrderHalfVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createSellOrder();
    order.takerWants = quoteFromBase(MID_PRICE - 9e18, fillVolume);
    order.takerGives = fillVolume;
  }

  function createSellOrderEvenLowerPriceAndLowerVolume() internal view returns (IOrderLogic.TakerOrder memory order) {
    uint fillVolume = 1 ether;
    order = createSellOrder();
    order.takerWants = quoteFromBase(MID_PRICE - 1e18, fillVolume);
    order.takerGives = fillVolume;
  }

  ///////////////////////
  /// Test maker side ///
  ///////////////////////

  function logOrderData(
    IMangrove iMgv,
    address taker,
    IOrderLogic.TakerOrder memory tko,
    IOrderLogic.TakerOrderResult memory res_
  ) internal {
    emit OrderSummary(
      iMgv,
      tko.outbound_tkn,
      tko.inbound_tkn,
      taker,
      tko.fillOrKill,
      tko.takerWants,
      tko.takerGives,
      tko.fillWants,
      tko.restingOrder,
      tko.expiryDate,
      res_.takerGot,
      res_.takerGave,
      res_.bounty,
      res_.fee,
      res_.offerId
    );
  }

  function test_empty_fill_buy_with_resting_order_is_correctly_posted_with_permit2_approvals() public {
    IOrderLogic.TakerOrder memory buyOrder = createBuyOrderLowerPrice();
    buyOrder.restingOrder = true;

    TransferLib.approveToken(quote, address(permit2), takerGives(buyOrder) * 2);
    IOrderLogic.TakerOrderResult memory expectedResult =
      IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 5});

    uint privKey = 0x1234;
    address fresh_taker = freshTakerForPermit2(0, takerGives(buyOrder), privKey);
    // generate permit to just in time approval
    IAllowanceTransfer.PermitSingle memory permit = getPermit(
      address(buyOrder.inbound_tkn), uint160(buyOrder.takerGives), EXPIRATION, NONCE, address(mgoWithPermit2.router())
    );

    bytes memory signature = getPermitSignature(permit, privKey, DOMAIN_SEPARATOR);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgoWithPermit2));
    logOrderData(IMangrove(payable(mgv)), fresh_taker, buyOrder, expectedResult);

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res =
      mgoWithPermit2.takeWithPermit{value: 0.1 ether}(buyOrder, permit, signature);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgoWithPermit2.provisionOf(quote, base, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgoWithPermit2.ownerOf(quote, base, res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(quote.balanceOf(fresh_taker), takerGives(buyOrder), "Incorrect remaining quote balance");
    assertEq(base.balanceOf(fresh_taker), 0, "Incorrect obtained base balance");
    // checking price of offer
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(quote), $(base), res.offerId);
    assertEq(offer.gives(), takerGives(buyOrder), "Incorrect offer gives");
    assertEq(offer.wants(), takerWants(buyOrder), "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgoWithPermit2), "Incorrect maker");
  }

  function test_empty_market_order_with_permit2_approvals() public {
    uint _takerWants = 1 ether;
    uint _takerGives = 1998 ether;
    bool fillWants = true;

    uint privKey = 0x1234;
    address fresh_taker = freshTakerForPermit2(0, _takerGives, privKey);
    // generate transfer permit for just in time approval

    ISignatureTransfer.PermitTransferFrom memory transferDetails =
      getPermitTransferFrom(address(quote), _takerGives, NONCE, EXPIRATION);

    bytes memory signature = getPermitTransferSignatureWithSpecifiedAddress(
      transferDetails, privKey, DOMAIN_SEPARATOR, address(mgoWithPermit2.router())
    );

    expectFrom(address(quote));
    emit Transfer(fresh_taker, address(mgoWithPermit2), _takerGives);

    vm.prank(fresh_taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgoWithPermit2.marketOrderWithTransferApproval(
      base, quote, _takerWants, _takerGives, fillWants, transferDetails, signature
    );

    assertEq(takerGot, 0 ether, "Incorrect taker got");
    assertEq(takerGave, 0, "Incorrect taker gave");
    assertEq(bounty, 0, "Offer bounty");
    assertEq(fee, 0, "Offer fee");
  }
}
