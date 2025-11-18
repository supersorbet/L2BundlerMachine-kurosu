# Gas Optimization

## Overview

The L1-L2 Ink Yield Bundler is designed with gas efficiency in mind, using modern Solidity optimization techniques and battle-tested libraries.

---

## Solady Libraries

The system uses **Solady** for gas-optimized operations:

### Ownable

Minimal storage overhead for ownership:
- Efficient ownership checks
- Gas-optimized transfers
- Minimal storage slots

```solidity
import {Ownable} from "solady/auth/Ownable.sol";

contract L1Depositor is Ownable {
    // Minimal ownership overhead
}
```

### ReentrancyGuard

Efficient guard implementation:
- Single storage slot
- Optimized check logic
- Minimal gas overhead

```solidity
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

function depositToL2(...) external nonReentrant {
    // Protected operations
}
```

### SafeTransferLib

Gas-optimized ERC20 transfers:
- Inline assembly optimizations
- Reduced gas costs
- Safe error handling

```solidity
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

SafeTransferLib.safeTransfer(token, to, amount);
```

---

## Storage Packing

### Packed Structs

Token status stored efficiently in minimal slots:

```solidity
struct TokenStatus {
    uint128 depositedAmount;  // 16 bytes
    uint128 currentBalance;   // 16 bytes
    uint128 yieldAvailable;   // 16 bytes
    uint32 lastUpdate;        // 4 bytes
    // Total: 52 bytes (fits in 2 slots)
}
```

### Benefits

- **Reduced Storage Slots**: Multiple values in single slot
- **Lower Gas Costs**: Fewer SSTORE operations
- **Efficient Reads**: Single SLOAD for multiple values
- **Optimized Writes**: Packed writes save gas

### Storage Layout

**Slot 1**: `depositedAmount` (128 bits) + `currentBalance` (128 bits)  
**Slot 2**: `yieldAvailable` (128 bits) + `lastUpdate` (32 bits) + padding (96 bits)

---

## Gas Optimization Techniques

### 1. Packed Storage

- Use appropriate integer sizes (`uint128` vs `uint256`)
- Pack related values together
- Minimize storage slot usage

### 2. Efficient Mappings

- Use mappings instead of arrays where possible
- Direct key-value lookups (O(1))
- No iteration overhead

### 3. Minimal External Calls

- Batch operations when possible
- Cache external call results
- Reduce cross-contract calls

### 4. Inline Assembly

- Used in Solady libraries
- Optimized low-level operations
- Reduced gas overhead

### 5. Event Optimization

- Emit events instead of storing historical data
- Minimal event data
- Efficient event encoding

---

## Gas Cost Comparison

### Storage Operations

**Unpacked (4 slots)**:
- Write: ~20,000 gas per slot = 80,000 gas total
- Read: ~2,100 gas per slot = 8,400 gas total

**Packed (2 slots)**:
- Write: ~20,000 gas per slot = 40,000 gas total ✅
- Read: ~2,100 gas per slot = 4,200 gas total ✅

**Savings**: ~50% reduction in storage gas costs

### Transfer Operations

**Standard Transfer**:
- ~21,000 gas base
- Additional gas for checks

**SafeTransferLib**:
- ~21,000 gas base
- Optimized checks ✅
- Reduced overhead ✅

---

## Optimization Best Practices

### 1. Use Appropriate Types

- `uint128` for token amounts (sufficient for most tokens)
- `uint32` for timestamps (covers ~136 years)
- `uint8` for percentages (0-100)

### 2. Minimize Storage Writes

- Cache values in memory
- Batch updates
- Use events for historical data

### 3. Efficient Loops

- Avoid unnecessary iterations
- Use mappings for lookups
- Early returns when possible

### 4. Function Optimization

- Keep functions focused
- Minimize external calls
- Use custom errors instead of strings

---

## Gas Cost Estimates

### Common Operations

**Deposit (L1 → L2)**:
- Token transfer: ~21,000 gas
- Bridge call: ~100,000 gas
- Storage updates: ~20,000 gas
- **Total**: ~141,000 gas

**Harvest (L2)**:
- Strategy withdrawal: ~50,000 gas
- Split calculation: ~5,000 gas
- Re-deposit: ~50,000 gas
- Bridge call: ~100,000 gas
- **Total**: ~205,000 gas

**Withdraw Yield (L1)**:
- Balance check: ~2,100 gas
- Token transfer: ~21,000 gas
- Storage update: ~20,000 gas
- **Total**: ~43,100 gas

---

## Related Documentation

- [Storage Layout](./storage.md) - Detailed storage optimization
- [Contract Responsibilities](./contracts.md) - Gas-efficient contract design
- [Security Architecture](./security.md) - Security without gas overhead

