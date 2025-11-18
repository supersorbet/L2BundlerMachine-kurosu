# System Architecture

## Overview

The Ink Yield Bundler architecture enables seamless cross-chain yield farming through a modular contract system designed for security, gas efficiency, and extensibility.

**Current Status**: V1 deployed on Ink L2 mainnet at [`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs) with Tydro lending. V2 adds multi-strategy support (Tydro + Velodrome + Slipstream) with helper contracts for zap operations and LP management.

---

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

---

## 📚 Documentation Sections

- **[Contract Mechanics](./contracts.md)** - Core contracts and helper contracts overview
- **[User Flows](./user-flows.md)** - Deposit and harvest flow diagrams
- **[Security Architecture](./security.md)** - Access control and safety mechanisms
- **[Storage Layout](./storage.md)** - Data structures and state management
- **[Bridge Architecture](./bridge.md)** - Across Protocol integration
- **[Yield Strategies](./yield-strategies.md)** - Strategy selection and allocation
- **[Factory Pattern](./factory.md)** - Vault deployment system
- **[Gas Optimization](./gas-optimization.md)** - Efficiency techniques
- **[Version History](./versions.md)** - V1 vs V2 comparison

---

## 🚀 Dive Deeper?

- [Core Contracts Documentation](../contracts/README.md)
- [Factory & Deployment Guide](../factory/README.md)
- [Yield Strategies Deep Dive](../strategies/README.md)
- [Bridge Integration Details](../bridge/README.md)
