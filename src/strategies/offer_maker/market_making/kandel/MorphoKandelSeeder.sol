pragma solidity ^0.8.10;

import {ERC4626KandelSeeder} from "./ERC4626KandelSeeder.sol";
import {MorphoVaultRouter, ERC4626Router} from "@mgv-strats/src/strategies/routers/integrations/MorphoVaultRouter.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IMorphoFactory} from "../../../interfaces/IMorphoFactory.sol";
import {IMorphoRewardDistributor} from "../../../interfaces/IMorphoRewardDistributor.sol";

///@title MorphoKandel strat deployer.
contract MorphoKandelSeeder is ERC4626KandelSeeder {
  IMorphoFactory public MORPHO_FACTORY;
  IMorphoRewardDistributor public MORPHO_REWARD_DISTRIBUTOR;

  ///@notice constructor for `ERC4626KandelSeeder`. Initializes an `MorphoVaultRouter` with this seeder as admin.
  ///@param mgv The Mangrove deployment.
  ///@param erc4626KandelGasreq the total gasreq to use for executing a kandel offer
  ///@param morphoFactory The Morpho factory contract.
  ///@param morphoRewardDistributor The Morpho reward distributor contract.
  constructor(
    IMangrove mgv,
    uint erc4626KandelGasreq,
    IMorphoFactory morphoFactory,
    IMorphoRewardDistributor morphoRewardDistributor
  ) ERC4626KandelSeeder(mgv, erc4626KandelGasreq) {
    MORPHO_FACTORY = morphoFactory;
    MORPHO_REWARD_DISTRIBUTOR = morphoRewardDistributor;
  }

  /// @inheritdoc ERC4626KandelSeeder
  function _deployRouter() internal override returns (ERC4626Router) {
    return new MorphoVaultRouter(MORPHO_FACTORY, MORPHO_REWARD_DISTRIBUTOR);
  }
}
