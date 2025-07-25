// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {PinnedEthereumFork} from "@mgv/test/lib/forks/Ethereum.sol";
import {ICToken} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {CompoundV2Router} from "@mgv-strats/src/strategies/routers/integrations/CompoundV2Router.sol";
import {CompoundKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/CompoundKandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";

/// @title CompoundKandel Test Contract
/// @notice Tests for Kandel strategy using Compound V2 Router
contract CompoundKandelTest is CoreKandelTest {
  PinnedEthereumFork fork;
  CompoundV2Router router;
  CompoundKandel compoundKandel;
  ICToken baseCToken;
  ICToken quoteCToken;

  receive() external payable {}

  /// @notice Set up the test environment with mock compound markets
  function __setForkEnvironment__() internal override {
    fork = new PinnedEthereumFork(22995414);
    fork.setUp();

    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;

    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    quote = TestToken(payable(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();
    setupMarket(olKey);
    baseCToken = ICToken(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    quoteCToken = ICToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
  }

  /// @notice Deploy Kandel with CompoundV2Router
  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    uint kandel_gasreq = 800_000;

    // Deploy Compound V2 Router
    router = new CompoundV2Router();

    // Set compound markets for base and quote tokens
    router.setMarket(ICToken(address(baseCToken)));
    router.setMarket(ICToken(address(quoteCToken)));

    // Create CompoundKandel with router
    compoundKandel = new CompoundKandel(
      mgv, olKey, kandel_gasreq, Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: strict})
    );

    // Bind router to kandel
    router.bind(address(compoundKandel));

    // Set admin
    compoundKandel.setAdmin(deployer);
    router.setAdmin(address(compoundKandel));

    // Give approval for kandel to pull tokens
    base.approve(address(compoundKandel), type(uint).max);
    quote.approve(address(compoundKandel), type(uint).max);

    return compoundKandel;
  }

  function precisionForAssert() internal pure override returns (uint) {
    return 1;
  }

  function getAbiPath() internal pure override returns (string memory) {
    return "/out/CompoundKandel.sol/CompoundKandel.json";
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.FUND_OWNER(), maker, "Incorrect owner");
    assertEq(base.balanceOf(address(router)), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(Ask) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(Bid) > 0, "Incorrect initial reserve balance of quote");
  }

  function test_first_offer_sends_first_puller_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }

  function test_not_first_offer_sends_proceed_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    // faking buffer on the router
    deal($(base), $(router), 1 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "", "Unexpected returned data");
  }

  function test_not_first_offer_sends_first_puller_to_posthook_when_buffer_is_small() public {
    MgvLib.SingleOrder memory order;
    order.olKey = olKey;
    order.takerWants = 0.1 ether;
    order.takerGives = 120 * 10 ** 6;
    // faking small buffer on the router
    deal($(base), $(router), 0.09 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }
}
