// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MangroveAmplifierDeployer} from "./MangroveAmplifierDeployer.s.sol";
import {
  MangroveAmplifier,
  IMangrove,
  RouterProxyFactory,
  SmartRouter
} from "@mgv-strats/src/strategies/MangroveAmplifier.sol";
import {BlastMangroveAmplifier} from "@mgv-strats/src/strategies/chains/blast/BlastMangroveAmplifier.sol";
import {BlastSmartRouter} from "@mgv-strats/src/strategies/chains/blast/routers/BlastSmartRouter.sol";

contract BlastMangroveAmplifierDeployer is MangroveAmplifierDeployer {
  function deployMangroveAmplifier(
    IMangrove mgv,
    RouterProxyFactory routerProxyFactory,
    SmartRouter _routerImplementation
  ) internal override returns (MangroveAmplifier mgvAmp) {
    BlastSmartRouter routerImplementation = BlastSmartRouter(address(_routerImplementation));
    broadcast();
    if (forMultisig) {
      mgvAmp = new BlastMangroveAmplifier{salt: salt}(mgv, routerProxyFactory, routerImplementation);
    } else {
      mgvAmp = new BlastMangroveAmplifier(mgv, routerProxyFactory, routerImplementation);
    }
  }
}
