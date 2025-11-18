# Introduction

**An extendable cross-chain yield aggregation protocol bridging Ethereum L1 to Ink L2**

[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FF6B6B?style=for-the-badge)](https://book.getfoundry.sh/) [![Ink L2](https://img.shields.io/badge/Ink-L2-6366F1?style=for-the-badge)](https://inkonchain.com) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE/)

***

## Overview

The Ink Yield Bundler enables seamless cross-chain yield farming between Ethereum L1 and Ink L2. Deposit assets on L1, automatically bridge to L2 for optimal yields, and receive returns on L1—all through private, owner-controlled vaults.

### Key Features

* 🔄 **Cross-Chain Bridging**: Seamless L1↔L2 transfers via Across Protocol
* 💰 **Multi-Strategy Yield**: Tydro (lending), Velodrome (LP), and Slipstream V3 (concentrated liquidity)
* 🏭 **Factory Pattern**: Deploy isolated private vault instances
* 🛡️ **Security First**: Owner-only operations with comprehensive safety mechanisms
* ⚡ **Gas Optimized**: Solady libraries for maximum efficiency
* 🤖 **Keeper-Friendly**: Permissionless auto-deposit and harvest functions
* 📊 **Smart Allocation**: Dynamic strategy selection via YieldAllocator
* 🚀 **Extensible**: Designed for easy integration of additional protocols

***

### [🏗️ Architecture](architecture/)

Deep dive into the system architecture, L1-L2 flow, and contract interactions.

### [📄 Core Contracts](contracts/)

Detailed documentation of all production contracts with code snippets.

### [🏭 Factory & Deployment](factory/)

Learn how to deploy your own private vault using the factory pattern.

### [💎 Yield Strategies](architecture/yield-strategies/strategies.md)

Explore supported yield strategies: Tydro lending and Velodrome liquidity provision.

### [🌉 Bridge Integration](bridge/)

Understand how cross-chain bridging works with Across Protocol.

### [👤 User Guide](user-guide/)

Step-by-step guide for users, including Gnosis Safe wallet integration.

### [🚀 Deployment Guide](broken-reference)

Complete deployment instructions for L1 and L2 contracts.

### [🗺️ Future Roadmap](ROADMAP.md)

Enhancement opportunities, Velodrome automation integration, and decentralized keeper infrastructure.

### [🧪 Testing & Verification](TESTING.md)

Comprehensive test suite documentation, test logs, and verification procedures.

***

## 🎯 Use Cases

**Private Treasury Management**: Deploy isolated vaults for full control over treasury assets.

**Institutional Yield Farming**: Automate yield generation across multiple strategies while maintaining L1 custody.

**DAO Operations**: Integrate with Gnosis Safe multisig for secure, multi-signature yield management.

***

## 🏛️ System Architecture

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────────┐
│   Ethereum L1   │         │  Across      │         │    Ink L2       │
│                 │         │  Bridge      │         │                 │
│  L1Depositor    │────────▶│              │────────▶│  Yield Vault    │
│                 │         │              │         │                 │
│  User Assets    │         │              │         │  Yield Strategies│
│  Yield Balance  │◀────────│              │◀────────│  (Tydro/Velo)   │
└─────────────────┘         └──────────────┘         └─────────────────┘
```

***

## 📊 Contract Overview

| Contract                         | Network     | Purpose                                                |
| -------------------------------- | ----------- | ------------------------------------------------------ |
| `L1DepositorV2_PRODUCTION`       | Ethereum L1 | Receives deposits, bridges to L2, manages yield        |
| `BundledYieldVaultV2_PRODUCTION` | Ink L2      | Manages yield strategies, harvests, bridges yield back |
| `YieldVaultFactory`              | Ink L2      | Deploys private vault instances for users              |
| `YieldAllocator`                 | Ink L2      | Smart multi-strategy allocation system                 |

***

## 🔐 Security

Owner-only operations, reentrancy protection, circuit breakers, slippage controls, and rate limiting ensure secure, controlled access to all vault functions.

***

## 📈 Yield Strategies

**Tydro** (Lending): ~3-5% APY, low risk, overcollateralized lending protocol.

**Velodrome** (LP): 20-50%+ APY, medium risk, liquidity provision with VELO rewards.

**Slipstream** (V3): Concentrated liquidity positions with customizable ranges and fee tiers.

**Curve Finance** (Planned): Priority integration for stablecoin pools (5-15% APY) pending funding.

***

## 🌐 Ecosystem

Built for **Ink L2** with integrations for Across Protocol (bridging), Tydro (lending), Velodrome (DEX), Slipstream (V3), and Gnosis Safe (multisig).

***

## 📝 License

MIT License - see [LICENSE](LICENSE/) file for details.

***

## 💰 Funding & Development Roadmap

**Current Status**: V1 deployed and operational on Ink L2 mainnet. V2 contracts complete with multi-strategy support.

**With Additional Funding**, we can deliver:

* 🤖 **Decentralized Keeper Network**: Permissionless automation infrastructure for hands-free vault operation
* 🔄 **Velodrome Automation Integration**: Advanced LP management leveraging proven automation patterns
* 📊 **Curve Finance Integration**: Priority stablecoin yield optimization (5-15% APY)
* 📊 **Analytics Dashboard**: Real-time monitoring and performance metrics
* 🌐 **Multi-Bridge Support**: Best-rate routing across multiple bridge protocols
* 📱 **Web Application**: User-friendly interface for vault management

**Impact**: Transform from functional yield aggregator to comprehensive, autonomous yield management platform. See [Roadmap](ROADMAP.md) for detailed plans.

***

**Built for the Ink/Kraken Ecosystem** 🚀

[Documentation](architecture/) • [Contracts](contracts/) • [Deployment](broken-reference)
