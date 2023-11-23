// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OfferForwarderTest} from "@mgv-strats/test/strategies/unit/OfferForwarder.t.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/aave/v3/IPool.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";

abstract contract BaseSimpleAaveLogic_Test is OfferForwarderTest {}
