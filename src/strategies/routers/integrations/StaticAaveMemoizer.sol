// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {AbstractAaveMemoizer} from "../abstract/AbstractAaveMemoizer.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow for a single owner.
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
contract StaticAaveMemoizer is AbstractAaveMemoizer {
  address internal immutable OWNER_ADDRESS;

  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode, address ownerAddress)
    AbstractAaveMemoizer(addressesProvider, interestRateMode)
  {
    OWNER_ADDRESS = ownerAddress;
  }

  ///@inheritdoc AbstractAaveMemoizer
  function getOwnerAddress(Memoizer memory) internal view virtual override returns (address) {
    return OWNER_ADDRESS;
  }
}
