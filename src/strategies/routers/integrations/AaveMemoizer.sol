// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.18;

import {AbstractAaveMemoizer} from "../abstract/AbstractAaveMemoizer.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow (for multiple owners).
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
contract AaveMemoizer is AbstractAaveMemoizer {
  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRateMode  interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  constructor(address addressesProvider, uint interestRateMode)
    AbstractAaveMemoizer(addressesProvider, interestRateMode)
  {}

  ///@inheritdoc AbstractAaveMemoizer
  function getOwnerAddress(Memoizer memory m) internal view virtual override returns (address owner) {
    bytes memory data = m.data;
    assembly {
      owner := mload(add(data, 20))
    }
    require(owner != address(0), "AaveMemoizer/OwnerNotSet");
  }

  /// @notice Sets the owner address in additional data
  /// @dev This uses the data field from the memoizer struct in order to have have a memoized value attached to a single owner.
  /// @param m the memoizer
  /// @param owner the owner address to set
  function setOwnerAddress(Memoizer memory m, address owner) internal pure {
    bytes memory data = m.data;
    assembly {
      mstore(add(data, 20), owner)
    }
  }
}
