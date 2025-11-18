# Introduction

**An extendable cross-chain yield aggregation protocol bridging Ethereum L1 to Ink L2**

[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FF6B6B?style=for-the-badge)](https://book.getfoundry.sh/) [![Ink L2](https://img.shields.io/badge/Ink-L2-6366F1?style=for-the-badge)](https://inkonchain.com) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE/)

***

## Overview

The L1-L2 InkBundler is an easy to use system that enables seamless yield farming across Ethereum (L1) and Ink L2. Users can deposit assets on L1, automatically bridge them to L2 for optimal yield opportunities, and receive yield back on L1—all while maintaining full control through private, owner-only vaults.

### Key Features

* 🔄 **Cross-Chain Bridging**: Seamless L1↔L2 transfers via Across Protocol
* 💰 **Multi-Strategy Yield**: Support for Tydro (lending) and Velodrome (liquidity provision)
* 🏭 **Factory Pattern**: Deploy your own private vault instances
* 🛡️ **Security First**: Owner-only operations, reentrancy guards, circuit breakers
* ⚡ **Gas Optimized**: Built with Solady for hyper efficiency
* 🤖 **Keeper-Friendly**: Auto-deposit and harvest functions for automation
* 📊 **Smart Allocation**: Dynamic yield strategy allocation via YieldAllocator utils
* 🚀 **Future-Ready**: Plans to integrate Curve.fi, Velodrome automation integration and decentralized keeper bots

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

### Private Treasury Management

Deploy your own private vault to manage treasury assets with full control and transparency.

### Institutional Yield Farming

Automate yield generation across multiple strategies while maintaining custody on L1.

### DAO Treasury Operations

Use Gnosis Safe multisig to manage cross-chain yield operations securely.

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

🔐 Security Features

* ✅ **Owner-Only Operations**: All critical functions are owner-restricted
* ✅ **Reentrancy Protection**: Solady ReentrancyGuard on all state-changing functions
* ✅ **Circuit Breakers**: Emergency pause and withdrawal limits
* ✅ **Slippage Protection**: Configurable slippage tolerance
* ✅ **Rate Limiting**: Anti-spam mechanisms and operation cooldowns
* ✅ **Access Control**: Comprehensive authorization checks

***

## 📈 Supported Yield Strategies

### Tydro (AAVE V3 Fork)

* **Type**: Lending Protocol
* **APY**: \~3-5% (varies by token)
* **Risk**: Low (overcollateralized lending)

### Velodrome

* **Type**: DEX Liquidity Provision
* **APY**: 20-50%+ (varies by pool)
* **Risk**: Medium (impermanent loss, trading fees)

### Curve Finance (Planned)

* **Type**: Stablecoin DEX
* **APY**: 5-15%+ (stablecoin pools)
* **Risk**: Low-Medium (optimized for stablecoins)
* **Status**: Priority integration in roadmap

***

## 🌐 Ecosystem Integration

This system is designed for the **Ink/Kraken ecosystem** and integrates with:

* **Ink L2**: Optimistic rollup infrastructure
* **Across Protocol**: Cross-chain bridging
* **Tydro**: AAVE V3 fork on Ink
* **Velodrome**: DEX on Ink L2
* **Gnosis Safe**: Multisig wallet support

***

## 📝 License

MIT License - see [LICENSE](LICENSE/) file for details.

***

## 🗺️ Future Enhancements

With additional funding, we plan to implement:

* 🤖 **Decentralized Keeper Network**: Permissionless keeper infrastructure for hands-free operation
* 🔄 **Velodrome Automation Integration**: Leverage [Velodrome's automation scripts](https://github.com/velodrome-finance/automations/tree/main/scripts) for advanced LP management
* 📊 **Curve Finance Integration**: Priority addition for stablecoin yield optimization
* 📊 **Advanced Analytics**: Real-time dashboards and on-chain metrics
* 🌐 **Multi-Bridge Support**: Additional bridge protocols for best-rate routing
* 📱 **Web Application**: Comprehensive user interface for vault management

***

**Built for the Ink/Kraken Ecosystem** 🚀

[Documentation](architecture/) • [Contracts](contracts/) • [Deployment](broken-reference)
