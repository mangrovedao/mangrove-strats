// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {
  IMangrove,
  AbstractRouter,
  OfferMaker,
  ILiquidityProvider,
  IERC20
} from "mgv_src/strategies/offer_maker/OfferMaker.sol";
import {ITesterContract} from "mgv_src/strategies/interfaces/ITesterContract.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AaveV3Borrower, ICreditDelegationToken} from "mgv_src/strategies/integrations/AaveV3Borrower.sol";
import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";

contract Keyrocker is ILiquidityProvider, OfferMaker, AaveV3Borrower {
  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, address deployer, uint gasreq, address addressesProvider)
    OfferMaker(mgv, NO_ROUTER, deployer, gasreq, address(0)) // reserveID is this contract
    AaveV3Borrower(addressesProvider, 0, 2)
  {}

  function tokenBalance(IERC20 token) external view returns (uint local, uint onPool, uint debt) {
    local = token.balanceOf(address(this));
    onPool = overlying(token).balanceOf(RESERVE_ID);
    debt = borrowed(address(token), RESERVE_ID);
  }

  function supply(IERC20 token, uint amount) public onlyAdmin {
    _supply(token, amount, RESERVE_ID, false);
  }

  function borrow(IERC20 token, uint amount) public onlyAdmin {
    _borrow(token, amount, RESERVE_ID);
  }

  function approveLender(IERC20 token, uint amount) public onlyAdmin {
    _approveLender(token, amount);
  }

  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint) {
    uint outboundBalance = IERC20(order.inbound_tkn).balanceOf(address(this));
    if (outboundBalance >= amount) {
      return 0;
    } else {
      amount = amount - outboundBalance;
      uint got = _redeemThenBorrow(IERC20(order.inbound_tkn), RESERVE_ID, amount, true, address(this));
      return (amount >= got ? amount - got : 0);
    }
  }

  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint) {
    _repayThenDeposit(IERC20(order.inbound_tkn), RESERVE_ID, amount);
    return 0;
  }

  function __activate__(IERC20 token) internal override {
    super.__activate__(token);
    _approveLender(token, type(uint).max);
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 maker_data)
    internal
    override
    returns (bytes32 data)
  {
    //reposting offer residual
    data = MangroveOffer.__posthookSuccess__(order, maker_data);
    require(
      data == REPOST_SUCCESS || data == COMPLETE_FILL,
      (data == "mgv/insufficientProvision")
        ? "mgv/insufficientProvision"
        : (data == "mgv/writeOffer/density/tooLow" ? "mgv/writeOffer/density/tooLow" : "posthook/failed")
    );
  }
}
