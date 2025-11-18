# Architecture Overview

## Overview

**Current Status**: V1 is deployed and operational on Ink L2 mainnet at [`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs), focusing on Tydro lending operations. V2 expands capabilities with multi-strategy support (Tydro + Velodrome) and includes zap utility peripheral contracts for seamless token swaps, one-click LP operations, and VELO token earning.

***

## 🏗️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Ethereum Mainnet (L1)                      │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         L1DepositorV2_PRODUCTION                         │  │
│  │  • Receives user deposits                                 │  │
│  │  • Bridges tokens to L2 via Across                       │  │
│  │  • Manages yield balance                                  │  │
│  │  • Owner-only operations                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           │ Across Bridge                       │
│                           ▼                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │
┌─────────────────────────────────────────────────────────────────┐
│                        Ink L2 Network                           │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │      BundledYieldVaultV2_PRODUCTION                     │  │
│  │  • Receives bridged tokens                               │  │
│  │  • Deposits to yield strategies                         │  │
│  │  • Harvests yield                                       │  │
│  │  • Bridges yield back to L1                             │  │
│  │  • Supports multi-strategy allocation                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│              ┌────────────┴────────────┐                         │
│              │                        │                         │
│      ┌───────▼──────┐        ┌───────▼──────┐                 │
│      │   Tydro      │        │  Velodrome   │                 │
│      │  (Lending)   │        │  (Liquidity) │                 │
│      └──────────────┘        └──────────────┘                 │
│                                      │                          │
│                           ┌──────────▼──────────┐              │
│                           │   Zap Utilities     │              │
│                           │  • Token swaps      │              │
│                           │  • One-click LP     │              │
│                           │  • VELO staking     │              │
│                           └─────────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

***

## 📚 Architecture Documentation

This architecture documentation is organized into focused sections:

* [**Contract Responsibilities**](contracts.md) - Detailed breakdown of L1Depositor and L2Vault contracts, their responsibilities, and key functions
* [**User Flows**](user-flows.md) - Complete deposit and harvest flow diagrams with sequence charts
* [**Security Architecture**](broken-reference) - Access control, reentrancy protection, and circuit breakers
* [**Storage Layout**](storage.md) - Storage structures, state management, and yield calculation
* [**Bridge Architecture**](broken-reference) - Across Protocol integration and bridge flow details
* [**Yield Strategies**](yield-strategies/) - Strategy selection, smart allocation, and compounding
* [**Factory Pattern**](factory.md) - Vault deployment and factory contract details
* [**Version History**](versions.md) - V1 (production) vs V2 (current) comparison

***

## 🚀 Dive Deeper?

* [Core Contracts Documentation](../contracts/)
* [Factory & Deployment Guide](../factory/)
* [Yield Strategies Deep Dive](yield-strategies/strategies.md)
* [Bridge Integration Details](../bridge/)
