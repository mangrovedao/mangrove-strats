// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@mgv/lib/IERC20.sol";

/// @title AbracadabraAddressProvider
/// @notice Provides a single source to find all the cauldrons for abracadabra by the underlying token.
contract AbracadabraAddressProvider {
  address private owner;

  mapping(address => address) public cauldrons;
  IERC20 public MIM;

  constructor(IERC20 mim) {
    MIM = mim;
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "AbracadabraAddressProvider/onlyOwner");
    _;
  }

  function transferOwnership(address newOwner) external onlyOwner {
    owner = newOwner;
  }

  function setCauldron(address underlying, address cauldron) external onlyOwner {
    cauldrons[underlying] = cauldron;
  }

  function setMIM(IERC20 mim) external onlyOwner {
    MIM = mim;
  }
}
