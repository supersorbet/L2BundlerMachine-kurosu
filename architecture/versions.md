# Version History

## Overview

The L1-L2 Ink Yield Bundler is currently on the V2 version, with V1 currently deployed and operational on Ink L2 mainnet, and V2 representing the next generation with expanded capabilities.

***

## V1 - Production

### Deployment

**L2 Vault Address**: [`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs)\
**Network**: Ink L2 Mainnet\
**Status**: ✅ Active and operational

### Key Features

* ✅ **Tydro Integration**: Full support for Tydro lending protocol
* ✅ **Cross-Chain Bridging**: Receives tokens from L1 via Across Protocol
* ✅ **Yield Harvesting**: Harvests accumulated yield from Tydro
* ✅ **Yield Bridging**: Bridges yield back to L1
* ✅ **Production Ready**: Live on mainnet with real transactions

### Limitations

* ⚠️ **Single Strategy**: Only supports Tydro (only tests)
* ⚠️ **Simplified Allocation**: No multi-strategy allocation
* ⚠️ **Basic Compounding**: Limited compounding options

### Contract Capabilities

The V1 vault focuses on the core lending functionality:

* Receives bridged tokens from L1
* Deposits tokens to Tydro lending pools
* Tracks yield accumulation
* Harvests yield periodically
* Bridges yield back to L1

### Transaction History

View live transactions on the [Ink Explorer](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs) to see:

* Token deposits from L1
* Tydro deposit operations
* Yield harvest transactions
* Yield bridging back to L1

***

## V2 -

### Features

* 🚀 **Multi-Strategy Support**: Tydro + Velodrome + Slipstream V3 (Curve Finance does not seem to have high enough volume on Ink, but will be implementing it in future versions for users to choose. With possible Tydro pools featuring curve tokens)
* 🚀 **Smart Allocation**: Dynamic strategy selection via YieldAllocator
* 🚀 **Advanced Compounding**: Flexible yield split (compound vs bridge)
* 🚀 **Enhanced Security**: Additional security mechanisms
* 🚀 **Gas Optimizations**: Hyper efficiency with Solady libraries
* 🚀 **Factory Pattern**: Deployable vault instances via YieldVaultFactory
* 🚀 **Helper Contracts**: VelodromeHelper and SlipstreamHelper for streamlined operations
  * VelodromeHelper: LP operations, zap functionality, VELO staking
  * SlipstreamHelper: Concentrated liquidity positions, NFT management, reward harvesting
* 🚀 **Zap Functionality**: One-click zap and add LP via VelodromeHelper
  * Single token to LP position in one transaction
  * Automatic token swapping to optimal ratios
  * Optional automatic staking for VELO rewards

***

## Related Documentation

* [Contract Mechanics](contracts.md) - Detailed contract capabilities
* [Yield Strategies](yield-strategies/) - Strategy details and differences
* [User Flows](user-flows.md) - How each version handles flows
