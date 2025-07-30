// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {CoreKandelTest} from "./abstract/CoreKandel.t.sol";
import {console} from "@mgv/forge-std/Test.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {ICToken} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";
import {TakaraLendRouter, IComptroller} from "@mgv-strats/src/strategies/routers/integrations/TakaraLendRouter.sol";
import {TakaraKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/compound/TakaraKandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvLib, OLKey, Offer, Global, Local} from "@mgv/src/core/MgvLib.sol";
import {GeometricKandel} from "@mgv-strats/src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {Direct} from "@mgv-strats/src/strategies/offer_maker/abstract/Direct.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {toFixed} from "@mgv/lib/Test2.sol";
import {TickLib} from "@mgv/lib/core/TickLib.sol";
import {AbstractRouter} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {GenericFork} from "@mgv/test/lib/forks/Generic.sol";

contract SeiFork is GenericFork {
  constructor() {
    CHAIN_ID = 1329;
    NAME = "sei"; // must be id used in foundry.toml for rpc_endpoint & etherscan
    NETWORK = "sei"; // must be network name inferred by ethers.js
  }
}

contract PinnedSeiFork is SeiFork {
  constructor(uint blockNumber) {
    BLOCK_NUMBER = blockNumber;
  }
}

/// @title TakaraKandel Test Contract
/// @notice Tests for Kandel strategy using Compound V2 Router
contract TakaraKandelTest is CoreKandelTest {
  using TransferLib for IERC20;

  address constant TAKARA_COMPTROLLER = 0x71034bf5eC0FAd7aEE81a213403c8892F3d8CAeE;
  address constant TAKARA_REWARD_DISTRIBUTOR = 0x28BF6D71b6Dc837F56F5afbF1F4A46AaC0B1f31E;
  address constant FASTUSDT_ADDRESS = 0x37a4dD9CED2b19Cfe8FAC251cd727b5787E45269;
  address constant USDT_ADDRESS = 0x9151434b16b9763660705744891fA906F660EcC5;
  address constant TFASTUSDT_ADDRESS = 0x92e51466482146E71b692ced2265284968E8B3d6;
  address constant TUSDT_ADDRESS = 0xA82a40324DBf7B57E87bD07C9e1D722E9754be9B;

  PinnedSeiFork fork;
  TakaraLendRouter router;
  TakaraKandel takaraKandel;
  ICToken baseCToken;
  ICToken quoteCToken;

  receive() external payable {}

  /// @notice Set up the test environment with mock compound markets
  function __setForkEnvironment__() internal override {
    fork = new PinnedSeiFork(159936788);
    fork.setUp();

    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;

    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    base = TestToken(payable(FASTUSDT_ADDRESS)); // fastUSD
    quote = TestToken(payable(USDT_ADDRESS)); // USDT
    baseCToken = ICToken(TFASTUSDT_ADDRESS); // tFastUSD
    quoteCToken = ICToken(TUSDT_ADDRESS); // tUSDT

    // Create the market key BEFORE calling setupMarket
    olKey = OLKey(address(base), address(quote), options.defaultTickSpacing);
    lo = olKey.flipped();

    // Now setup the market with the fork-compatible addresses
    setupMarket(olKey);
  }

  /// @notice Deploy Kandel with TakaraLendRouter
  function __deployKandel__(address deployer, address id, bool strict)
    internal
    virtual
    override
    returns (GeometricKandel)
  {
    uint kandel_gasreq = 800_000;

    // Deploy Compound V2 Router
    router = new TakaraLendRouter(IComptroller(TAKARA_COMPTROLLER));

    // Create TakaraKandel with router
    takaraKandel = new TakaraKandel(
      mgv, olKey, kandel_gasreq, Direct.RouterParams({routerImplementation: router, fundOwner: id, strict: strict})
    );

    // Bind router to kandel
    router.bind(address(takaraKandel));

    // Set admin
    takaraKandel.setAdmin(deployer);
    router.setAdmin(address(takaraKandel));

    vm.startPrank(deployer);
    // Set compound markets for base and quote tokens
    takaraKandel.setMarket(ICToken(address(baseCToken)));
    takaraKandel.setMarket(ICToken(address(quoteCToken)));
    vm.stopPrank();

    return takaraKandel;
  }

  function precisionForAssert() internal pure override returns (uint) {
    return 1;
  }

  function getAbiPath() internal pure override returns (string memory) {
    return "/out/TakaraKandel.sol/TakaraKandel.json";
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

  function test_claim_reward() public {
    vm.warp(block.timestamp + 2 days);
    // TODO: why is this reverting if function signature is ok?
    vm.prank(takaraKandel.admin());
    takaraKandel.claimReward();
  }

  // function test_first_offer_sends_first_puller_to_posthook() public {
  //   MgvLib.SingleOrder memory order;
  //   order.olKey = olKey;
  //   order.takerWants = 0.1 ether;
  //   order.takerGives = 120 * 10 ** 6;
  //   vm.prank($(mgv));
  //   bytes32 makerData = kdl.makerExecute(order);
  //   assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  // }

  // function test_not_first_offer_sends_proceed_to_posthook() public {
  //   MgvLib.SingleOrder memory order;
  //   order.olKey = olKey;
  //   order.takerWants = 0.1 ether;
  //   order.takerGives = 120 * 10 ** 6;
  //   // faking buffer on the router
  //   deal($(base), $(router), 1 ether);
  //   vm.prank($(mgv));
  //   bytes32 makerData = kdl.makerExecute(order);
  //   assertEq(makerData, "", "Unexpected returned data");
  // }

  // function test_not_first_offer_sends_first_puller_to_posthook_when_buffer_is_small() public {
  //   MgvLib.SingleOrder memory order;
  //   order.olKey = olKey;
  //   order.takerWants = 0.1 ether;
  //   order.takerGives = 120 * 10 ** 6;
  //   // faking small buffer on the router
  //   deal($(base), $(router), 0.09 ether);
  //   vm.prank($(mgv));
  //   bytes32 makerData = kdl.makerExecute(order);
  //   assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  // }
}
