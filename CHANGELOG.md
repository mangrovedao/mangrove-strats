# Next version

- feat: add `UniSwap` routing logic, manager, and univ3 logics

# 2.1.0-1

- Upgrade to @mangrovedao/mangrove-deployments v2.1.1
- Upgrade to @mangrovedao/context-addresses v1.2.0
- Add Orbit lend to the routing logics

# 2.1.0-0

- Add support for blast

# 2.0.1

- Create `SmartRouter` schema to allow to plug any `RoutingLogic` to a `Forwarder` contract
- Create `RouterProxyFactory` to deploy router proxies for each user and allow all approvals to a single contract per user
- Add `RenegingForwarder` to allow time based and volume based reneging
- Change `IOfferLogic` `router` view function to be passed an argument, supposedly the 'owner' of the router
- Add a `router` view function with no args to `Direct` contract because `Direct` only needs a single router
- Change `MangroveOrder`
  - Default Router is now a proxied Smart Router
  - `take` entrypoints args changed
    - Removed `fillOrKill` and `restingOrder` boolean args
    - Added `takerOrderType` enum with GTC(E), IOC, FOK, and PO orders
  - `MangroveOrder` now extends `RenegingForwarder`
- Add `MangroveAmplifier` to amplify create offers on multiple market from a single token
  - Possibility to attach a logic to every token
  - Bundle-wise reneging on time possibility
- Add ABI exports for `MangroveAmplifier`, `AbstractRoutingLogic`, `SimpleAaveLogic`, and `AavePooledRouter`
- Add Aave Routing logic
- Add Mock Aave Oracle to `AaveMock` contract
- Add deployer for `SimpleAaveLogic`
- Remove mangrove.js deployer
- Bump @mangrovedao/context-addresses to v1.1.2
- Bump @mangrovedao/mangrove-deployments to v2.0.2
- Simplify copying of context addresses

# 1.0.2

- Add support for Sepolia
- Remove double deployment of (Aave)Kandel instances on Mumbai
- Bump @mangrovedao/mangrove-core to v2.0.3
- Bump @mangrovedao/context-addresses to v1.0.1
- Bump @mangrovedao/mangrove-deployments to v1.0.2

# 1.0.1

- Change @mangrovedao/mangrove-core dependency from 'next' to '^2.0.0'
- Change @mangrovedao/mangrove-deployments and @mangrovedao/context-addresses dependencies from 'next' to '^1.0.0'

# 1.0.0

The Mangrove strat lib and strategies have been separated out into this repo and package. It used to be part of @mangrovedao/mangrove-core where a description of earlier changes can also be found.

Strat lib and strategies have been updated to Mangrove v2.
The main changes are:

- 'pivotId' removed as Mangrove v2 now has constant-gas insert and update and doesn't use a pivot
- '(gives, wants)' changed to '(gives, tick)' for offer making
- '(gives, wants)' changed to '(fillVolume, tick)' for offer taking
- Events changed to use 'OLKey' and streamlined
- 'gasprice' is now 26 bits in Mwei
- 'MangroveOffer': 'residualGives' and 'residualWants' removed. Replaced with 'residualValues' which by default keeps price ('tick') and calculates remaining 'gives' like before
- SimpleRouter: Now inherits from a MonoRouter to specify that it only has a single-sourcing perspective.
- MangroveOrder: The ability to reuse an old, owned offer id is added.
- Kandel strategy changes:
  - Conceptual change: Do not calculate price of offers and create them on the fly in the posthook, instead allocate all offers up front, and set their price.
  - Cross-cutting: Refactoring to reduce bytecode size, deduplicating some functions.
  - Reduced complexity significantly by removing compounding parameter and initializing all Kandel offers up front with their price (tick) stored in the core protocol
  - Forwards calls to generate the offer distribution to populate a geometric Kandel instance to the new KandelLib which has a 'createGeometricDistribution'. This on-chain generation function in KandelLib is introduced to reduce call data size for L2s. A library is used to reduce contract size.
  - Introduced a 'baseQuoteTickOffset' to replace the old 'ratio' parameter. Since prices in the core protocol follow a geometric progression, we offset via adding a tick offset, instead of multiplying by a ratio. All other parameters moved to CoreKandel.
  - Reduced complexity, and using offsets for price differences means we can support much larger price differences.
  - Spread renamed to step size.
  - Distribution struct changed to containing structs instead of arrays to reduce bytecode size and save gas.
  - 'populate' and 'populateIndex' changed to be able to "reserve" offers on the offer list by creating and retracting offers up front if 'gives' in the offer distribution is 0 for said offer. This is to avoid having to create offers during 'posthook' since it is expensive and complicates logic. Note, since the core protocol does not accept 0 gives, we have to use a minimum gives based on the density requirements of the core protocol.
  - Kandel added for contract verification as KandelLib address to use by SDK

Licenses have been updated:

- All code is now licensed under the MIT License, with the exception of 3rd party code.
- 3rd party code in src/strategies/vendor/ is still covered by the original licences.

Addresses are now read from the @mangrovedao/mangrove-deployments and @mangrovedao/context-addresses npm packages.

The unused AAVE v2 integration has been removed.
