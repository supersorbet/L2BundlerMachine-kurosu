# System Architecture

## 🏗️ Contract Overview

This system consists of multiple contracts supporting L1-L2 cross-chain yield aggregation:

### **L1 Contracts (Ethereum Mainnet)**

1. **L1DepositorV2_PRODUCTION.sol**
   - Receives deposits from users
   - Bridges tokens to Ink L2 via **Across Bridge**
   - Receives and manages yield from L2
   - Token mapping (L1 → L2 tokens)

### **L2 Contracts (Ink L2)**

#### Option 1: Across Bridge Approach
**BundledYieldVaultV2_PRODUCTION.sol**
   - Receives bridged tokens via Across
   - Deposits to **Tydro** pools
   - Harvests yield
   - Bridges yield back via **Across**
   - Supports yield compounding

#### Option 2: Relay Protocol Approach (NEW) ⭐
**YieldManagerWithBridge.sol**
   - Uses **Relay Protocol** for L1 transfers (https://docs.relay.link)
   - Supports **multiple yield strategies**:
     - **Tydro** (AAVE V3 fork) - Lending
     - **Velodrome** - Liquidity provision
   - Unified harvest with auto 50/50 split
   - Batch operations support
   - Intent-based bridging (similar to Across, optimized for Ink L2)

## 🔄 Flow Comparison

### **Across Bridge Flow:**
```
User → L1Depositor → Across HubPool → Ink L2 → BundledYieldVault → Tydro → Harvest → Across SpokePool → L1Depositor
```

### **Relay Protocol Flow:**
```
User → L1Depositor → Relay Depository (L1) → Relayer fills on L2 → YieldManager → [Tydro OR Velodrome] → Harvest → Relay Depository (L2) → Relayer fills on L1 → L1Recipient
```

## 📊 Feature Comparison

| Feature | BundledYieldVault | YieldManagerWithBridge |
|---------|------------------|----------------------|
| Bridge Type | Across | Relay Protocol |
| Yield Strategies | Tydro only | Tydro + Velodrome |
| Compound % | Configurable | Fixed 50/50 |
| Batch Operations | ❌ | ✅ |
| Gas Efficiency | Good (~77k deposit, ~120k fill) | Similar (~77k deposit, ~120k fill) |
| Protocol Support | Tydro | Tydro + Velodrome |
| Ink L2 Native | ❌ | ✅ |

## 🎯 Which to Use?

### **Use BundledYieldVaultV2_PRODUCTION if:**
- ✅ You want Across Bridge integration (cross-chain liquidity)
- ✅ Simple Tydro-only strategy
- ✅ Configurable compound percentage
- ✅ Already set up with Across

### **Use YieldManagerWithBridge if:**
- ✅ You want Relay Protocol integration (Ink L2's bridge solution)
- ✅ Multiple yield strategies (Tydro + Velodrome)
- ✅ Batch operations for efficiency
- ✅ Optimized for Ink L2 specifically
- ✅ Intent-based bridging (similar to Across but Ink-native)

## 🔧 Interfaces

### Bridge Interfaces
- `IAcross.sol` - Across HubPool & SpokePool
- `IRelay.sol` - Relay Protocol (Depository, Hub, Oracle)
- ~~`IL2StandardBridge.sol`~~ - Not available on Ink (uses Relay instead)

### Protocol Interfaces
- `ITydro.sol` - Simple Tydro interface (for BundledYieldVault)
- `ITydroAAVE.sol` - Full AAVE V3-style Tydro interface (for YieldManager)
- `IVelodrome.sol` - Velodrome DEX interface

## 🚀 Deployment Strategy

### **Option A: Across Bridge**
1. Deploy `L1DepositorV2_PRODUCTION` on Ethereum
2. Deploy `BundledYieldVaultV2_PRODUCTION` on Ink
3. Configure token mappings
4. Set up Across relayers

### **Option B: Relay Protocol**
1. Deploy `L1DepositorV2_PRODUCTION` on Ethereum (could use Relay on L1 too)
2. Deploy `YieldManagerWithBridge` on Ink (uses Relay Depository on L2)
3. Configure token mappings
4. Set up Relay Protocol integration (relayers will handle fills)

### **Option C: Hybrid**
- Use Across for L1→L2 deposits
- Use Native bridge for L2→L1 yield transfers
- Best of both worlds!

## 📝 Next Steps

1. **Decide on bridge strategy**: Across vs Native vs Hybrid
2. **Create L1 contract** that works with native bridge (if using Option B/C)
3. **Deploy to testnet** and verify integrations
4. **Gas profiling** comparison between approaches
5. **Security audit** for production

## 🎨 Code Style

All contracts follow **Solady** patterns:
- Gas-optimized libraries
- Custom errors
- Packed structs
- Assembly where beneficial
- Consistent formatting

