const fs = require("fs");
const path = require("path");

// Contracts that should export their ABI only
exports.abi_exports = [
  "MangroveOrder",
  "AbstractRouter",
  "ICreditDelegationToken",
  "ILiquidityProvider",
  "IOfferLogic",
  "AccessControlled",
  "GeometricKandel",
  "CoreKandel",
  "Kandel",
  "AaveKandel",
  "AbstractKandelSeeder",
  "KandelSeeder",
  "AaveKandelSeeder",
  "RouterProxyFactory",
  "SmartRouter",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = [];

/////////////////////////////////////
// mangrove-deployments configuration

// Whether to fetch deployments from mangrove-deployments.
// Setting this to false allows manually specifying the addresses to use
// by writing them to the JSON files in the addresses/deployed directory.
// This may be useful if one wants to use a non-primary deployment.
// Default is true.
exports.copyDeployments = true;

// The SemVer range describing the versions of the Mangrove strat contracts
// to query mangrove-deployments for.
// Default is the latest patch of the current package version.
const packageVersion = require("./package.json").version;
exports.stratsDeploymentVersionRangePattern = `^${packageVersion}`;

// Whether to query mangrove-deployments for released (true), unreleased (false),
// or the latest of either (undefined) versions of the strat contracts.
// Default is the latest regardless of their release status.
exports.stratsDeploymentVersionReleasedFilter = undefined;

// The SemVer range describing the versions of the Mangrove core contracts
// to query mangrove-deployments for.
// Default is the latest patch of the currently installed version of mangrove-core.
const mangroveCorePackagePath = path.join(
  __dirname,
  "node_modules",
  "@mangrovedao",
  "mangrove-core",
  "package.json",
);
const mangroveCoreVersion = require(mangroveCorePackagePath).version;
exports.coreDeploymentVersionRangePattern = `^${mangroveCoreVersion}`;

// Whether to query mangrove-deployments for released (true), unreleased (false),
// or the latest of either (undefined) versions of the core contracts.
// Default is the latest regardless of their release status.
exports.coreDeploymentVersionReleasedFilter = undefined;

//////////////////////////////////
// context-addresses configuration

// Whether to fetch deployments from context-addresses.
// Setting this to false allows manually specifying the addresses to use
// by writing them to the JSON files in the addresses/context directory.
// Default is true.
exports.copyContextAddresses = true;
