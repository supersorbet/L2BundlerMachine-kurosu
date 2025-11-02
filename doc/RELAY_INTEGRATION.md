# Relay Protocol Integration

## ✅ Fixed: Now Using Relay Protocol

**Previously:** Contracts incorrectly assumed native L2StandardBridge  
**Now:** Properly integrated with [Relay Protocol](https://docs.relay.link/references/protocol/overview) for Ink L2

## 🔄 Relay Protocol Overview

Relay is an intent-based cross-chain payment system similar to Across, designed to minimize gas costs and enable rapid chain expansion. Key components:

- **Relay Depository** - Where users deposit funds on origin chain
- **Relay Hub** - Tracks deposits and fills
- **Relay Oracle** - Verifies that fills were correctly executed
- **Relay Vaults** - Used by relayers to rebalance across chains

## 📊 Flow Comparison

### **Relay Protocol Flow (Ink L2):**
```
L1: User → Relay Depository (L1) → Relayer fills on L2 → Hub tracks → Oracle verifies → Relayer settles
L2: YieldManager → Relay Depository (L2) → Relayer fills on L1 → Hub tracks → Oracle verifies → Relayer settles
```

### **Current Implementation:**

1. **L1DepositorV2_PRODUCTION.sol**
   - Currently uses Across Bridge (IHubPool)
   - **Could be updated to use Relay Depository on L1** for consistency

2. **YieldManagerWithBridge.sol** ✅ **UPDATED**
   - Now uses `IRelayDepository` on L2 (Ink)
   - Bridges yield back to L1 via Relay Protocol
   - Supports Tydro + Velodrome strategies

## 🔧 Interface Changes

### **New Interface: `IRelay.sol`**
```solidity
interface IRelayDepository {
    function deposit(
        uint256 destinationChainId,
        address recipient,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint256 deadline
    ) external returns (bytes32 depositId);
}
```

### **Updated: YieldManagerWithBridge.sol**
- ❌ Removed: `IL2StandardBridge` (doesn't exist on Ink)
- ✅ Added: `IRelayDepository` (actual Relay Protocol)
- Changed: `bridgeGasLimit` → `maxBridgeFee` (basis points)
- Changed: `L2_STANDARD_BRIDGE` → `RELAY_DEPOSITORY`

## 📝 Deployment Notes

### **For YieldManagerWithBridge on Ink L2:**

1. **Get Relay Depository Address on Ink:**
   ```bash
   # Check Relay Protocol docs for Ink L2 depository address
   export RELAY_DEPOSITORY="0x..." # Relay Depository on Ink L2
   ```

2. **Deploy with Relay:**
   ```bash
   forge create src/YieldManagerWithBridge.sol:YieldManagerWithBridge \
     --rpc-url $INK_RPC \
     --private-key $PRIVATE_KEY \
     --constructor-args \
       $RELAY_DEPOSITORY \  # Relay Depository on Ink
       $TYDRO_POOL \
       $VELO_ROUTER \
       $L1_RECIPIENT
   ```

3. **Set Bridge Fee:**
   ```solidity
   yieldManager.setMaxBridgeFee(100); // 1% (100 bps)
   ```

## 🎯 Next Steps

### **Option 1: Keep Current L1 (Across)**
- L1 uses Across Bridge (already implemented)
- L2 uses Relay Protocol (now updated)
- Hybrid approach works fine

### **Option 2: Unify on Relay** (Recommended)
- Update `L1DepositorV2_PRODUCTION` to use Relay Depository on L1
- Fully unified Relay Protocol integration
- Simpler architecture, single bridge protocol

### **Option 3: Multiple Bridge Support**
- Support both Across and Relay
- Let users/admin choose which bridge to use
- Maximum flexibility

## 🔍 Verification

After deployment, verify Relay integration:

1. **Check deposit creation:**
   ```solidity
   // When harvesting, check events
   event DepositInitiated(bytes32 indexed depositId, ...);
   ```

2. **Monitor Relay Hub:**
   ```solidity
   // Check if deposit is tracked
   IRelayHub(RELAY_HUB).getDeposit(depositId);
   ```

3. **Verify fills:**
   ```solidity
   // Oracle verification
   IRelayOracle(RELAY_ORACLE).verifyFill(...);
   ```

## 📚 Resources

- [Relay Protocol Docs](https://docs.relay.link/references/protocol/overview)
- [Relay GitHub](https://github.com/relay-link) (for contract ABIs)
- [Relay App](https://app.relay.link) (reference UI)

## ⚠️ Important Notes

1. **Relay is intent-based** - Relayers front capital and fill optimistically
2. **Settlement is optimistic** - No need to prove every fill, challenge period instead
3. **Batch settlement** - Done infrequently to amortize costs
4. **Gas efficient** - Designed to minimize deposit and fill costs (~77k and ~120k gas)
5. **Ink L2 specific** - This integration is specifically for Ink L2, which uses Relay

