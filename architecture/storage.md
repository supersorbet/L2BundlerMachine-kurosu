# Storage Layout

## Overview

This document describes the storage structures and state management in the L1-L2 Ink Yield Bundler contracts.

---

## L1Depositor Storage

### Core Mappings

```solidity
mapping(address => address) public tokenMapping;  // L1 → L2 token mapping
mapping(address => uint256) public yieldBalance;  // Accumulated yield per token
```

### Configuration Variables

```solidity
address public l2Vault;                            // L2 vault address
uint64 public maxSlippageBps;                     // Max slippage (basis points)
```

### Storage Breakdown

- **tokenMapping**: Maps L1 token addresses to their corresponding L2 token addresses
  - Used to determine destination token when bridging
  - Set via `setTokenMapping()` (owner-only)
  
- **yieldBalance**: Tracks accumulated yield per token on L1
  - Updated when yield is bridged back from L2
  - Decremented when users withdraw yield
  
- **l2Vault**: Address of the BundledYieldVaultV2 contract on Ink L2
  - Used as recipient address when bridging tokens
  
- **maxSlippageBps**: Maximum acceptable slippage in basis points (1 bps = 0.01%)
  - Used to validate minimum amounts in bridge operations
  - Configurable via owner functions

---

## L2Vault Storage

### Token Status Structure

```solidity
struct TokenStatus {
    uint128 depositedAmount;  // Amount deposited to strategies
    uint128 currentBalance;   // Current balance in strategies
    uint128 yieldAvailable;   // Accumulated yield
    uint32 lastUpdate;        // Last update timestamp
}
```

### Core Mappings

```solidity
mapping(address => TokenStatus) public tokenStatus;
mapping(address => address) public tokenMapping;  // L2 → L1 token mapping
```

### Configuration Variables

```solidity
address public l1Recipient;                       // L1 depositor address
```

### Storage Breakdown

**TokenStatus Fields**:
- **depositedAmount**: Original principal amount deposited to strategies
  - Set when tokens are first deposited
  - Used as baseline for yield calculation
  
- **currentBalance**: Current total balance in strategies
  - Updated after deposits and withdrawals
  - Includes both principal and accrued yield
  
- **yieldAvailable**: Calculated yield ready to harvest
  - Formula: `yieldAvailable = currentBalance - depositedAmount`
  - Reset after harvesting
  
- **lastUpdate**: Timestamp of last status update
  - Used for rate limiting and tracking
  - Updated on every state change

**Storage Packing**:
- `uint128` fields: 16 bytes each (3 fields = 48 bytes)
- `uint32` field: 4 bytes
- **Total**: 52 bytes (fits efficiently in 2 storage slots)

---

## State Management

### Token Status Tracking

The vault maintains comprehensive state for each token:

1. **Deposit**: When tokens arrive from L1
   - `depositedAmount` = amount received
   - `currentBalance` = amount received
   - `yieldAvailable` = 0
   - `lastUpdate` = block.timestamp

2. **Strategy Deployment**: When tokens are deposited to strategies
   - `depositedAmount` = unchanged (original principal)
   - `currentBalance` = updated with strategy balance
   - `yieldAvailable` = recalculated

3. **Yield Accrual**: Over time, strategies generate yield
   - `currentBalance` increases
   - `yieldAvailable` = `currentBalance - depositedAmount`

4. **Harvest**: When yield is harvested
   - `yieldAvailable` = 0 (harvested)
   - `depositedAmount` = updated if compounding
   - `currentBalance` = updated after withdrawal

### Yield Calculation

```solidity
yieldAvailable = currentBalance - depositedAmount
```

Yield is harvested periodically and split between:
- **Compound**: Re-deposited to increase `depositedAmount`
- **Bridge**: Sent back to L1 and tracked in `yieldBalance`

---

## Gas Optimization

### Storage Packing

The `TokenStatus` struct is optimized for storage efficiency:

- Uses `uint128` for amounts (sufficient for most tokens)
- Uses `uint32` for timestamps (covers ~136 years)
- Packs multiple values into minimal storage slots
- Reduces SLOAD/SSTORE operations

### Storage Access Patterns

- Frequently accessed data (tokenStatus) uses single mapping lookup
- Infrequently changed data (config) uses separate storage variables
- Event emissions used instead of storage for historical data

---

## Related Documentation

- [Contract Responsibilities](./contracts.md) - How storage is used in contract functions
- [Gas Optimization](./gas-optimization.md) - Storage optimization techniques
- [User Flows](./user-flows.md) - State transitions in user flows

