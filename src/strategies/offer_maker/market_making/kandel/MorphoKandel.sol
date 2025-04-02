// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC4626Kandel} from "./ERC4626Kandel.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {MorphoVaultRouter} from "../../../routers/integrations/MorphoVaultRouter.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";

///@title A Kandel strat that uses Morpho vaults for yield generation
contract MorphoKandel is ERC4626Kandel {
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param olKeyBaseQuote The OLKey for the outbound_tkn base and inbound_tkn quote offer list Kandel will act on, the flipped OLKey is used for the opposite offer list.
  ///@param gasreq the gas required by the strat to execute
  ///@param routerParams routing policy parameters for this contract
  constructor(IMangrove mgv, OLKey memory olKeyBaseQuote, uint gasreq, RouterParams memory routerParams)
    ERC4626Kandel(mgv, olKeyBaseQuote, gasreq, routerParams)
  {}

  ///@notice Returns the router as a MorphoVaultRouter
  ///@return The MorphoVaultRouter.
  function morphoRouter() private view returns (MorphoVaultRouter) {
    return MorphoVaultRouter(address(router()));
  }

  ///@notice Claims rewards for a specific token
  ///@param token The token for which to claim rewards
  ///@param amount The amount of rewards to claim
  ///@param proof The proof for claiming rewards
  ///@param receiver The address that will receive the claimed rewards
  ///@dev Only callable by the admin
  function claimRewardsForToken(IERC20 token, uint amount, bytes32[] calldata proof, address receiver)
    external
    onlyAdmin
  {
    morphoRouter().claimRewardsForToken(token, amount, proof, receiver);
  }
}
