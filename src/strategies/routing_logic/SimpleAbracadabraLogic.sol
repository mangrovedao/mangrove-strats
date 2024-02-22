// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.20;

import {AbstractRoutingLogic, IERC20} from "./abstract/AbstractRoutingLogic.sol";
import {AbracadabraLender} from "@mgv-strats/src/strategies/integrations/abracadabra/Lender.sol";
import {ICauldronV4} from "../vendor/abracadabra/interfaces/ICauldronV4.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

// TODO: Add addressbook to track cauldrons

/// @title SimpleAbracadabraLogic
/// @notice Routing logic for Abracadabra without credit line
contract SimpleAbracadabraLogic is AbracadabraLender, AbstractRoutingLogic {
  IERC20 public immutable MIM;

  ///@notice contract's constructor
  ///@param magicInternetMoney ERC20 contract for the MIM contract used as overlying for all cauldrons
  constructor(IERC20 magicInternetMoney, ICauldronV4 cauldron) AbracadabraLender(cauldron) {
    MIM = magicInternetMoney;
  }

  ///@inheritdoc AbstractRoutingLogic
  function pullLogic(IERC20 token, address fundOwner, uint amount, bool strict) external override returns (uint pulled) {
    uint amount_ = strict ? amount : overlyingBalanceOf(fundOwner);
    if (amount_ == 0) {
      return 0;
    }
    // fetching overlyings from owner's account
    // will fail if `address(this)` is not approved for it.
    require(
      TransferLib.transferTokenFrom(overlying(token), fundOwner, address(this), amount_),
      "SimpleAbracadabraLogic/pullFailed"
    );
    // redeem from the cauldron and send underlying to calling maker contract
    (, pulled) = _redeem(token, amount_, msg.sender, false);
  }

  ///@inheritdoc AbstractRoutingLogic
  function pushLogic(IERC20 token, address fundOwner, uint amount) external override returns (uint pushed) {
    // funds are on MakerContract, they need first to be transferred to this contract before being deposited
    require(
      TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "SimpleAbracadabraLogic/pushFailed"
    );

    // just in time approval of the cauldron in order to be able to deposit funds
    _approveLender(token, amount);
    bytes32 reason = _supply(token, amount, fundOwner, true);
    require(reason == bytes32(0), string(abi.encodePacked(reason)));
    return amount;
  }

  ///@notice fetches and memoizes the token balance of `this` contract
  ///@param token the asset whose balance is needed.
  ///@param owner the balance owner
  ///@return balance of the asset
  function balanceOf(IERC20 token, address owner) internal view returns (uint) {
    return token.balanceOf(owner);
  }

  ///@inheritdoc AbstractRoutingLogic
  function balanceLogic(IERC20 token, address fundOwner) external view override returns (uint balance) {
    balance = overlyingBalanceOf(fundOwner);
  }

  ///@notice fetches the balance of the overlying of the asset (always MIM)
  ///@param owner the balance owner
  ///@return balance of the overlying of the asset
  function overlyingBalanceOf(address owner) internal view returns (uint) {
    return MIM.balanceOf(owner);
  }
}
