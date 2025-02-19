pragma solidity ^0.8.10;

import {IMorphoFactory} from "src/strategies/interfaces/IMorphoFactory.sol";

contract MockMorphoFactory is IMorphoFactory {
  // Mock state variables
  mapping(address => bool) public vaults;

  // Function to add a vault
  function setVault(address token, bool isVault) external {
    vaults[token] = isVault;
  }

  // Mock function to check if an address is a Morpho vault
  function isMorphoVault(address vault) external view override returns (bool) {
    // For testing, assume the mock vault address is a Morpho vault
    return vaults[vault];
  }
}
