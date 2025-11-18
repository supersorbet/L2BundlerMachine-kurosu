# Security Architecture

## Overview

The L1-L2 Ink Yield Bundler implements multiple layers of security to protect user funds and ensure system integrity.

---

## Access Control

### Owner-Only Operations

All critical operations are **owner-only** to prevent unauthorized access:

```solidity
modifier onlyOwner() {
    if (msg.sender != owner()) revert Unauthorized();
    _;
}
```

### Protected Functions

**L1Depositor**:
- `depositToL2()` - Only owner can initiate deposits
- `withdrawYield()` - Only owner can withdraw yield
- `setTokenMapping()` - Only owner can configure token mappings
- `setMaxSlippage()` - Only owner can adjust slippage tolerance

**L2Vault**:
- `depositAvailable()` - Only owner can trigger deposits
- `harvestAndBridge()` - Only owner can harvest yield
- `depositToTydro()` - Only owner can deploy to strategies
- `deployToVelodrome()` - Only owner can create LP positions

---

## Reentrancy Protection

### Solady ReentrancyGuard

All state-changing functions use Solady's efficient ReentrancyGuard:

```solidity
function depositToL2(...) external onlyOwner nonReentrant {
    // Safe operations
}
```

### Protection Scope

- ✅ External token transfers
- ✅ Bridge interactions
- ✅ Strategy deposits/withdrawals
- ✅ Yield harvesting operations

---

## Circuit Breakers

Multiple safety mechanisms prevent system abuse and protect funds:

### 1. Emergency Pause

Contracts can be paused to stop all operations instantly:
- Prevents new deposits
- Stops yield harvesting
- Blocks bridge operations
- Allows emergency withdrawals

### 2. Rate Limiting

Prevents spam and excessive operations:
- Minimum time between operations
- Maximum operations per time period
- Per-token operation limits

### 3. Withdrawal Limits

Daily limits per token:
- Maximum yield withdrawal per day
- Prevents large-scale drain attacks
- Configurable per token

### 4. Slippage Protection

Configurable max slippage tolerance:
- Prevents unfavorable bridge rates
- Validates minimum amounts
- Protects against MEV attacks

---

## Security Best Practices

### 1. Input Validation

All functions validate inputs:
- Non-zero amounts
- Valid token addresses
- Reasonable percentage values (0-100)
- Valid chain IDs

### 2. State Consistency

- Atomic operations prevent partial state updates
- Reentrancy guards prevent state corruption
- Storage packing reduces attack surface

### 3. Bridge Security

- Validates Across Protocol callbacks
- Verifies recipient addresses
- Checks bridge amounts match expectations

### 4. Strategy Security

- Validates strategy contract addresses
- Checks strategy return values
- Verifies receipt token balances

---

## Audit Considerations

The system is designed with auditability in mind:

- ✅ Clear access control patterns
- ✅ Comprehensive event emissions
- ✅ Minimal external dependencies
- ✅ Gas-optimized but readable code
- ✅ Standard Solady security libraries

---

## Related Documentation

- [Contract Responsibilities](./contracts.md) - Security implications of contract functions
- [Storage Layout](./storage.md) - Storage security considerations
- [Bridge Architecture](./bridge.md) - Bridge security mechanisms

