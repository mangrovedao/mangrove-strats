// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OrbitSpaceStation} from "@orbit-protocol/contracts/SpaceStation.sol";
import {OrbitPriceOracle} from "./OrbitPriceOracle.sol";
import {OErc20} from "@orbit-protocol/contracts/OErc20.sol";
import {OErc20Delegator} from "@orbit-protocol/contracts/Core/CErc20Delegator.sol";
import {OErc20Delegate} from "@orbit-protocol/contracts/Core/CErc20Delegate.sol";

import {IERC20} from "@mgv/lib/IERC20.sol";
import {JumpRateModelV2} from "@orbit-protocol/contracts/InterestRate/JumpRateModelV2.sol";
import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";
import {Blast} from "@mgv/src/toy/blast/Blast.sol";
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";
import {OToken} from "@orbit-protocol/contracts/OToken.sol";

import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";

contract OrbitDeployer {
  OrbitSpaceStation internal spaceStation;
  OrbitPriceOracle internal orbitPriceOracle;
  JumpRateModelV2 internal jumpRateModel;
  OErc20Delegate internal oTokenDelegate;

  function deployOrbit() internal {
    spaceStation = new OrbitSpaceStation();
    orbitPriceOracle = new OrbitPriceOracle();
    spaceStation._setPriceOracle(orbitPriceOracle);
    jumpRateModel = new JumpRateModelV2(0, 11_312, 246_602, 800000000000000000, address(this));
    oTokenDelegate = new OErc20Delegate();
  }

  function addMarket(IERC20 token) internal returns (OErc20 oToken) {
    oToken = OErc20(
      address(
        new OErc20Delegator(
          address(token),
          spaceStation,
          jumpRateModel,
          200024784666402,
          string.concat("o", token.name()),
          string.concat("o", token.symbol()),
          token.decimals(),
          payable(address(this)),
          address(oTokenDelegate),
          ""
        )
      )
    );
    spaceStation._supportMarket(OToken(address(oToken)));
  }
}
