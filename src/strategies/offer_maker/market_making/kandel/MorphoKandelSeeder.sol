// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626KandelSeeder} from "./ERC4626KandelSeeder.sol";
import {MorphoVaultRouter, ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/MorphoVaultRouter.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IMorphoFactory} from "../../../interfaces/IMorphoFactory.sol";
import {IMorphoRewardDistributor} from "../../../interfaces/IMorphoRewardDistributor.sol";
import {ERC4626RouterDeployer} from "./ERC4626RouterDeployer.sol";
import {MorphoRouterDeployer} from "./MorphoRouterDeployer.sol";

///@title MorphoKandel strat deployer.
contract MorphoKandelSeeder is ERC4626KandelSeeder {
  IMorphoFactory public immutable MORPHO_FACTORY;
  IMorphoRewardDistributor public immutable MORPHO_REWARD_DISTRIBUTOR;
  MorphoRouterDeployer public immutable morphoRouterDeployer;

  ///@notice constructor for `MorphoKandelSeeder`. Initializes an `MorphoVaultRouter` with this seeder as admin.
  ///@param mgv The Mangrove deployment.
  ///@param erc4626KandelGasreq the total gasreq to use for executing a kandel offer
  ///@param morphoFactory The Morpho factory contract.
  ///@param morphoRewardDistributor The Morpho reward distributor contract.
  ///@param _routerDeployer The ERC4626RouterDeployer contract
  ///@param _morphoRouterDeployer The MorphoRouterDeployer contract
  constructor(
    IMangrove mgv,
    uint erc4626KandelGasreq,
    IMorphoFactory morphoFactory,
    IMorphoRewardDistributor morphoRewardDistributor,
    ERC4626RouterDeployer _routerDeployer,
    MorphoRouterDeployer _morphoRouterDeployer
  ) ERC4626KandelSeeder(mgv, erc4626KandelGasreq, _routerDeployer) {
    MORPHO_FACTORY = morphoFactory;
    MORPHO_REWARD_DISTRIBUTOR = morphoRewardDistributor;
    morphoRouterDeployer = _morphoRouterDeployer;
  }

  /// @inheritdoc ERC4626KandelSeeder
  function _deployRouter() internal override returns (ERC4626Router) {
    return morphoRouterDeployer.deployRouter(MORPHO_FACTORY, MORPHO_REWARD_DISTRIBUTOR);
  }
}
