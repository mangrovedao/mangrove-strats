// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  Kandel, IERC20, IMangrove, OfferType
} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {CoreKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {AbstractKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandel.sol";
import {GeometricKandel} from "mgv_strat_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {toFixed} from "mgv_lib/Test2.sol";
import {OLKey} from "mgv_src/MgvLib.sol";
import {LogPriceConversionLib} from "mgv_lib/LogPriceConversionLib.sol";

/**
 * @notice Populates Kandel's distribution on Mangrove
 */

/**
 * KANDEL=Kandel_WETH_USDC FROM=0 TO=100 FIRST_ASK_INDEX=50 PRICE_POINTS=100\
 *    [RATIO=10100] [LOG_PRICE_OFFSET=769] SPREAD=1 INIT_QUOTE=$(cast ff 6 100) VOLUME=$(cast ff 18 0.1)\
 *    forge script KandelPopulate --fork-url $LOCALHOST_URL --private-key $MUMBAI_PRIVATE_KEY --broadcast
 */

contract KandelPopulate is Deployer {
  function run() public {
    GeometricKandel kdl = Kandel(envAddressOrName("KANDEL"));
    Kandel.Params memory params;
    uint24 logPriceOffset;
    if (envHas("LOG_PRICE_OFFSET")) {
      logPriceOffset = uint24(vm.envUint("LOG_PRICE_OFFSET"));
      require(logPriceOffset == vm.envUint("LOG_PRICE_OFFSET"), "Invalid LOG_PRICE_OFFSET");
    }
    if (envHas("RATIO")) {
      require(logPriceOffset == 0, "Only RATIO or LOG_PRICE_OFFSET");
      int _logPriceOffset =
        LogPriceConversionLib.logPriceFromVolumes(1 ether * uint(vm.envUint("RATIO")) / (100000), 1 ether);
      logPriceOffset = uint24(uint(int(_logPriceOffset)));
      require(logPriceOffset == uint(_logPriceOffset), "Invalid ratio");
    }
    params.pricePoints = uint8(vm.envUint("PRICE_POINTS"));
    require(params.pricePoints == vm.envUint("PRICE_POINTS"), "Invalid PRICE_POINTS");
    params.spread = uint8(vm.envUint("SPREAD"));
    require(params.spread == vm.envUint("SPREAD"), "Invalid SPREAD");

    innerRun(
      HeapArgs({
        from: vm.envUint("FROM"),
        to: vm.envUint("TO"),
        firstAskIndex: vm.envUint("FIRST_ASK_INDEX"),
        logPriceOffset: logPriceOffset,
        params: params,
        initQuote: vm.envUint("INIT_QUOTE"),
        volume: vm.envUint("VOLUME"),
        kdl: kdl,
        mgvReader: MgvReader(envAddressOrName("MGV_READER", "MgvReader"))
      })
    );
  }

  ///@notice Arguments for innerRun
  ///@param initQuote the amount of quote tokens that Kandel must want/give at `from` index
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param provBid the amount of provision (in native tokens) that are required to post a fresh bid
  ///@param provAsk the amount of provision (in native tokens) that are required to post a fresh ask
  ///@param kdl the Kandel instance
  ///@param mgv is kdl.MGV()
  ///@param base is kdl.BASE()
  ///@param quote is kdl.QUOTE()
  ///@param mgvReader the MgvReader

  struct HeapArgs {
    uint from;
    uint to;
    uint firstAskIndex;
    uint24 logPriceOffset;
    Kandel.Params params;
    uint initQuote;
    uint volume;
    GeometricKandel kdl;
    MgvReader mgvReader;
  }

  struct HeapVars {
    CoreKandel.Distribution bidDistribution;
    CoreKandel.Distribution askDistribution;
    uint baseAmountRequired;
    uint quoteAmountRequired;
    bool bidding;
    uint snapshotId;
    uint lastOfferId;
    uint gasreq;
    uint gasprice;
    MgvReader mgvReader;
    IERC20 BASE;
    IERC20 QUOTE;
    uint provAsk;
    uint provBid;
  }

  function innerRun(HeapArgs memory args) public {
    HeapVars memory vars;

    vars.mgvReader = args.mgvReader;
    vars.BASE = args.kdl.BASE();
    vars.QUOTE = args.kdl.QUOTE();
    (
      vars.gasprice,
      vars.gasreq,
      /*uint8 spread*/
      ,
      /*uint8 length*/
    ) = args.kdl.params();

    OLKey memory olKeyBaseQuote =
      OLKey({outbound: address(vars.BASE), inbound: address(vars.QUOTE), tickScale: args.kdl.TICK_SCALE()});
    vars.provAsk = vars.mgvReader.getProvision(olKeyBaseQuote, vars.gasreq, vars.gasprice);
    vars.provBid = vars.mgvReader.getProvision(olKeyBaseQuote.flipped(), vars.gasreq, vars.gasprice);
    uint funds = (vars.provAsk + vars.provBid) * (args.to - args.from);
    if (broadcaster().balance < funds) {
      console.log(
        "Broadcaster does not have enough funds to provision offers. Missing",
        toFixed(funds - broadcaster().balance, 18),
        "native tokens"
      );
      require(false, "Not enough funds");
    }

    prettyLog("Calculating base and quote...");
    (vars.bidDistribution, vars.askDistribution) = calculateBaseQuote(args);

    prettyLog("Evaluating required collateral...");
    evaluateAmountsRequired(vars);
    // after the above call, `vars.base/quoteAmountRequired` are filled
    uint baseDecimals = vars.BASE.decimals();
    uint quoteDecimals = vars.QUOTE.decimals();
    prettyLog(
      string.concat(
        "Required collateral of base is ",
        toFixed(vars.baseAmountRequired, baseDecimals),
        " and quote is ",
        toFixed(vars.quoteAmountRequired, quoteDecimals)
      )
    );

    string memory deficit;

    if (vars.BASE.balanceOf(broadcaster()) < vars.baseAmountRequired) {
      deficit = string.concat(
        "Not enough base (",
        vm.toString(address(vars.BASE)),
        "). Deficit: ",
        toFixed(vars.baseAmountRequired - vars.BASE.balanceOf(broadcaster()), baseDecimals)
      );
    }
    if (vars.QUOTE.balanceOf(broadcaster()) < vars.quoteAmountRequired) {
      deficit = string.concat(
        bytes(deficit).length > 0 ? string.concat(deficit, ". ") : "",
        "Not enough quote (",
        vm.toString(address(vars.QUOTE)),
        "). Deficit: ",
        toFixed(vars.quoteAmountRequired - vars.QUOTE.balanceOf(broadcaster()), quoteDecimals)
      );
    }
    if (bytes(deficit).length > 0) {
      deficit = string.concat("broadcaster: ", vm.toString(broadcaster()), " ", deficit);
      prettyLog(deficit);
      revert(deficit);
    }

    prettyLog("Approving base and quote...");
    broadcast();
    vars.BASE.approve(address(args.kdl), vars.baseAmountRequired);
    broadcast();
    vars.QUOTE.approve(address(args.kdl), vars.quoteAmountRequired);

    prettyLog("Populating Mangrove...");

    broadcast();

    args.kdl.populate{value: funds}(
      vars.bidDistribution, vars.askDistribution, args.params, vars.baseAmountRequired, vars.quoteAmountRequired
    );
    console.log(toFixed(funds, 18), "native tokens used as provision");
  }

  function calculateBaseQuote(HeapArgs memory args)
    public
    pure
    returns (CoreKandel.Distribution memory bidDistribution, CoreKandel.Distribution memory askDistribution)
  {
    int baseQuoteLogPriceIndex0 = LogPriceConversionLib.logPriceFromVolumes(args.initQuote, args.volume);
    (bidDistribution, askDistribution) = args.kdl.createDistribution(
      args.from,
      args.to,
      baseQuoteLogPriceIndex0,
      int(uint(args.logPriceOffset)),
      args.firstAskIndex,
      type(uint).max,
      args.volume,
      args.params.pricePoints,
      args.params.spread
    );
  }

  ///@notice evaluates required amounts that need to be published on Mangrove
  ///@dev we use foundry cheats to revert all changes to the local node in order to prevent inconsistent tests.
  function evaluateAmountsRequired(HeapVars memory vars) public pure {
    for (uint i = 0; i < vars.bidDistribution.givesDist.length; ++i) {
      vars.quoteAmountRequired += vars.bidDistribution.givesDist[i];
    }
    for (uint i = 0; i < vars.askDistribution.givesDist.length; ++i) {
      vars.baseAmountRequired += vars.askDistribution.givesDist[i];
    }
  }
}
