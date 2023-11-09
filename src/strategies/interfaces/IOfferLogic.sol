// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import {IERC20, IMaker, OLKey} from "@mgv/src/core/MgvLib.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";

///@title IOfferLogic interface for offer management
///@notice It is an IMaker for Mangrove.

interface IOfferLogic is IMaker {
  ///@notice Log incident (during post trade execution)
  ///@param olKeyHash the hash of the offer list key. This is indexed so that RPC calls can filter on it.
  ///@param offerId the Mangrove offer id. This is indexed so that RPC calls can filter on it.
  ///@param makerData from the maker.
  ///@param mgvData from Mangrove.
  ///@notice By emitting this data, an indexer can keep track of what incidents has happened.
  event LogIncident(bytes32 indexed olKeyHash, uint indexed offerId, bytes32 makerData, bytes32 mgvData);

  ///@notice Approves a spender to transfer a certain amount of tokens on behalf of `this`.
  ///@param token the ERC20 token contract
  ///@param spender the approved spender
  ///@param amount the spending amount
  ///@return result of token approval.
  ///@dev admin may use this function to revoke specific approvals of `this` that are set after a call to `activate`.
  function approve(IERC20 token, address spender, uint amount) external returns (bool);

  ///@notice computes the amount of native tokens that can be redeemed when deprovisioning a given offer.
  ///@param olKey the offer list key.
  ///@param offerId the identifier of the offer in the offer list
  ///@return provision the amount of native tokens that can be redeemed when deprovisioning the offer
  function provisionOf(OLKey memory olKey, uint offerId) external view returns (uint provision);

  ///@notice verifies that this contract's current state is ready to be used execute a given list of routing orders.
  ///@param routingOrders the routingOrders one wishes to check
  ///@dev throws with a reason if something (e.g. an approval) is missing.
  function checkList(RL.RoutingOrder[] calldata routingOrders) external view;

  /// @notice performs the required approvals so as to allow `this` to interact with Mangrove on a set of assets.
  /// @param activateOrders routing orders containing at least the token to activate and the amount.
  function activate(RL.RoutingOrder[] calldata activateOrders) external;

  ///@notice withdraws native tokens from `this` balance on Mangrove.
  ///@param amount the amount of WEI one wishes to withdraw.
  ///@param receiver the address of the receiver of the funds.
  ///@dev Since a call is made to the `receiver`, this function is subject to reentrancy.
  function withdrawFromMangrove(uint amount, address payable receiver) external;

  ///@notice Memory allocation for `_new/updateOffer`'s arguments.
  ///@param olKey the offer list key.
  ///@param tick the tick.
  ///@param gives the amount of outbound tokens the maker gives for a complete fill.
  ///@param gasreq the amount of gas units that are required to execute the trade
  ///@param gasprice the gasprice used to compute offer's provision (use 0 to use Mangrove's gasprice)
  ///@param fund WEIs in `this` contract's balance that are used to provision the offer.
  ///@param noRevert is set to true if calling function does not wish `_newOffer` to revert on error.
  ///@param owner the offer maker managing the offer.
  ///@dev `owner` is required in `Forwarder` logics, when `_newOffer` or `_updateOffer` in called in a hook (`msg.sender==MGV`).
  struct OfferArgs {
    OLKey olKey;
    Tick tick;
    uint gives;
    uint gasreq;
    uint gasprice;
    uint fund;
    bool noRevert;
  }

  /// @notice Contract's router getter.
  /// @return the router.
  /// @dev if contract has a no router, function returns `NO_ROUTER`.
  function router() external view returns (AbstractRouter);

  /// @notice Contract's Mangrove getter
  /// @return the Mangrove contract.
  function MGV() external view returns (IMangrove);
}
