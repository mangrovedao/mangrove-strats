// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv-strats/test/lib/StratTest.sol";
import {
  KandelSeeder,
  IMangrove,
  GeometricKandel
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {
  AaveKandelSeeder,
  AavePooledRouter,
  IPoolAddressesProvider
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {AbstractKandelSeeder} from
  "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {
  SmartKandelSeeder,
  SmartKandel,
  RouterProxyFactory
} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/SmartKandelSeeder.sol";

import {SmartRouter} from "@mgv-strats/src/strategies/routers/SmartRouter.sol";

contract KandelSeederTest is StratTest {
  PinnedPolygonFork internal fork;
  AbstractKandelSeeder internal seeder;
  AbstractKandelSeeder internal aaveSeeder;
  AbstractKandelSeeder internal smartSeeder;
  AavePooledRouter internal aaveRouter;
  SmartRouter internal smartRouter;
  RouterProxyFactory internal factory;

  event NewAaveKandel(
    address indexed owner,
    bytes32 indexed baseQuoteOlKeyHash,
    bytes32 indexed quoteBaseOlKeyHash,
    address aaveKandel,
    address reserveId
  );
  event NewKandel(
    address indexed owner, bytes32 indexed baseQuoteOlKeyHash, bytes32 indexed quoteBaseOlKeyHash, address kandel
  );
  event NewSmartKandel(
    address indexed owner, bytes32 indexed baseQuoteOlKeyHash, bytes32 indexed quoteBaseOlKeyHash, address kandel
  );

  function sow(bool sharing) internal returns (GeometricKandel) {
    return seeder.sow({olKeyBaseQuote: olKey, liquiditySharing: sharing});
  }

  function sowAave(bool sharing) internal returns (GeometricKandel) {
    return aaveSeeder.sow({olKeyBaseQuote: olKey, liquiditySharing: sharing});
  }

  function sowSmart(bool sharing) internal returns (GeometricKandel) {
    return smartSeeder.sow({olKeyBaseQuote: olKey, liquiditySharing: sharing});
  }

  function setEnvironment() internal {
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH.e"));
    quote = TestToken(fork.get("USDC.e"));
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();
    setupMarket(olKey);
  }

  function setUp() public virtual override {
    /// sets base, quote, opens a market (base,quote) on Mangrove
    setEnvironment();
    seeder = new KandelSeeder({mgv: IMangrove($(mgv)), kandelGasreq: 128_000});

    AaveKandelSeeder aaveKandelSeeder = new AaveKandelSeeder({
      mgv: IMangrove($(mgv)),
      addressesProvider: IPoolAddressesProvider(fork.get("AaveAddressProvider")),
      aaveKandelGasreq: 628_000
    });
    aaveSeeder = aaveKandelSeeder;
    aaveRouter = aaveKandelSeeder.AAVE_ROUTER();

    smartRouter = new SmartRouter(address(0));
    factory = new RouterProxyFactory();

    smartSeeder = new SmartKandelSeeder({
      mgv: IMangrove($(mgv)),
      kandelGasreq: 128_000,
      factory: factory,
      routerImplementation: smartRouter
    });
  }

  function test_sow_fails_if_market_not_fully_active() public {
    mgv.deactivate(olKey);
    vm.expectRevert("KandelSeeder/inactiveMarket");
    sow(false);
    mgv.activate(olKey, 0, 10, 50_000);
    mgv.deactivate(lo);
    vm.expectRevert("KandelSeeder/inactiveMarket");
    sow(false);
  }

  function test_aave_manager_is_attributed() public {
    assertEq(aaveRouter.aaveManager(), address(this), "invalid aave Manager");
  }

  function test_logs_new_aaveKandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(aaveSeeder));
    emit NewAaveKandel(maker, olKey.hash(), olKey.flipped().hash(), 0x9f92659F6b974ce0c1C144F57dbE5981bCdFa515, maker);
    vm.prank(maker);
    sowAave(true);
  }

  function test_logs_new_kandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(seeder));
    emit NewKandel(maker, olKey.hash(), olKey.flipped().hash(), 0x42add52666C78960A219b157a1F4DbF806CbF703);
    vm.prank(maker);
    sow(true);
  }

  function test_logs_new_smartKandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(smartSeeder));
    emit NewSmartKandel(maker, olKey.hash(), olKey.flipped().hash(), 0x8BE005c5AB08D68aE72Ad21a6177CE26704e4A71);
    vm.prank(maker);
    sowSmart(true);
  }

  function checkListAavePooledRouter(IERC20 token, GeometricKandel kdl, address fundOwner) internal {
    AavePooledRouter router = AavePooledRouter(address(kdl.router()));
    deal({to: address(kdl), token: address(token), give: 10});
    vm.prank(address(kdl));
    router.pushAndSupply(token, 10, IERC20(address(0)), 0, fundOwner);

    vm.prank(address(kdl));
    router.pull(RL.createOrder({token: token, fundOwner: fundOwner}), 5, true);
  }

  function test_maker_deploys_shared_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sowAave(true);

    assertEq(address(kdl.router()), address(aaveRouter), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), kdl.admin(), "Incorrect owner");

    checkListAavePooledRouter(base, kdl, address(this));
    checkListAavePooledRouter(quote, kdl, address(this));
  }

  function test_maker_deploys_private_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sowAave(false);

    assertEq(address(kdl.router()), address(aaveRouter), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), address(kdl), "Incorrect owner");

    // checking router is ready to be used
    checkListAavePooledRouter(base, kdl, address(kdl));
    checkListAavePooledRouter(quote, kdl, address(kdl));
  }

  function test_maker_deploys_kandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sow(false);

    assertEq(address(kdl.router()), address(0), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), address(kdl), "Incorrect owner");
  }

  function test_maker_deploys_smartKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sowSmart(false);

    address router = factory.computeProxyAddress(maker, smartRouter);

    assertEq(address(kdl.router()), router, "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), maker, "Incorrect owner");
  }
}
