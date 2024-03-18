// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {
  SmartKandelSeeder,
  SmartKandel,
  RouterProxyFactory
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/SmartKandelSeeder.sol";
import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {PoolAddressProviderMock} from "@mgv-strats/script/toy/AaveMock.sol";
import {AaveCaller, IPoolAddressesProvider} from "@mgv-strats/test/lib/agents/AaveCaller.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {AbstractRoutingLogic} from "@mgv-strats/src/strategies/routing_logic/abstract/AbstractRoutingLogic.sol";

contract SmartKandelTest is CoreKandelTest {
  PinnedPolygonFork fork;
  SimpleAaveLogic logic;
  SmartKandel kandel;
  bool useForkAave = true;
  IPoolAddressesProvider aave;
  RouterProxyFactory factory;
  SmartRouter routerImplementation;

  receive() external payable {}

  function router() internal view returns (SmartRouter) {
    return SmartRouter(factory.computeProxyAddress(maker, routerImplementation));
  }

  function __setForkEnvironment__() internal override {
    if (useForkAave) {
      fork = new PinnedPolygonFork(39880000);
      fork.setUp();
      options.gasprice = 90;
      options.gasbase = 68_000;
      options.defaultFee = 30;
      mgv = setupMangrove();
      reader = new MgvReader($(mgv));
      base = TestToken(fork.get("WETH.e"));
      quote = TestToken(fork.get("USDC.e"));
      olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
      lo = olKey.flipped();
      setupMarket(olKey);
      aave = IPoolAddressesProvider(fork.get("AaveAddressProvider"));
    } else {
      super.__setForkEnvironment__();
      aave = IPoolAddressesProvider(address(new PoolAddressProviderMock(dynamic([address(base), address(quote)]))));

      // Assume tokens behave weirdly here
      base.transferResponse(TestToken.MethodResponse.MissingReturn);
      quote.approveResponse(TestToken.MethodResponse.MissingReturn);
    }
    factory = new RouterProxyFactory();
    routerImplementation = new SmartRouter(address(0));
    logic = new SimpleAaveLogic(aave, 2);
  }

  function __deployKandel__(address deployer, address, bool) internal virtual override returns (GeometricKandel) {
    uint kandel_gasreq = 1_000_000;
    SmartKandel _kandel = new SmartKandel({
      mgv: IMangrove($(mgv)),
      olKeyBaseQuote: olKey,
      gasreq: kandel_gasreq,
      owner: deployer,
      factory: factory,
      routerImplementation: routerImplementation
    });
    _kandel.setAdmin(deployer);

    vm.startPrank(deployer);
    _kandel.router().bind(address(_kandel));
    base.approve(address(_kandel.router()), type(uint).max);
    quote.approve(address(_kandel.router()), type(uint).max);
    // _kandel.setLogics(logic, logic, 0);
    // logic.overlying(base).approve(address(_kandel.router()), type(uint).max);
    // logic.overlying(quote).approve(address(_kandel.router()), type(uint).max);
    vm.stopPrank();
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20

    return _kandel;
  }

  function precisionForAssert() internal pure override returns (uint) {
    return 1;
  }

  function getAbiPath() internal pure override returns (string memory) {
    return "/out/SmartKandel.sol/SmartKandel.json";
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), maker, "Incorrect owner");
    assertEq(base.balanceOf(address(router())), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router())), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(Ask) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(Bid) > 0, "Incorrect initial reserve balance of quote");
    assertEq(base.balanceOf(maker), kdl.reserveBalance(Ask), "Router should have all its base on AAVE");
    assertEq(quote.balanceOf(maker), kdl.reserveBalance(Bid), "Router should have all its quote on AAVE");
  }

  function test_allExternalFunctions_differentCallers_correctAuth() public virtual override {
    super.test_allExternalFunctions_differentCallers_correctAuth();
    SmartKandel kdl_ = SmartKandel(payable(address(kdl)));

    kdl_.PROXY_FACTORY();
    kdl_.getLogics();

    CheckAuthArgs memory args;
    args.callee = $(kdl);
    args.callers = dynamic([address($(mgv)), maker, $(this), $(kdl)]);
    args.revertMessage = "AccessControlled/Invalid";
    // Only admin
    args.allowed = dynamic([address(maker)]);
    checkAuth(args, abi.encodeCall(kdl_.setLogics, (logic, logic, 0)));
  }

  function test_set_logics_get_logis() public {
    SmartKandel kdl_ = SmartKandel(payable(address(kdl)));

    vm.prank(maker);
    kdl_.setLogics(logic, logic, 0);

    (AbstractRoutingLogic baseLogic, AbstractRoutingLogic quoteLogic) = kdl_.getLogics();
    assertEq(address(baseLogic), address(logic), "Incorrect base logic");
    assertEq(address(quoteLogic), address(logic), "Incorrect quote logic");
  }

  // these tests don't make sense as balance can be in user wallet

  function test_reserveBalance_withoutOffers_returnsFundAmount() public override {}

  function test_reserveBalance_withOffers_returnsFundAmount() public override {}

  function test_pending_withoutOffers_returnsReserveBalance() public override {}

  function test_pending_withOffers_disregardsOfferedVolume() public override {}
}
