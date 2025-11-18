# Yield Strategy Architecture

## Overview

The BundledYieldVault supports multiple yield strategies to maximize returns while managing risk. This document describes strategy selection, allocation, and compounding mechanisms.

**V1 Status**: Currently deployed on Ink L2 mainnet at [`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs), focusing exclusively on Tydro operations with proven mainnet transactions.

**V2**: The contract system is set to significantly expand in V2 with multi-strategy support. 

---

## Strategy Selection

### V1 - Production (Current)

**V1 Vault** ([`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs)) currently supports:
- ✅ **Tydro (Lending)**: Full production support with live mainnet transactions

### V2 - 

The vault will support multiple yield strategies:

1. **Tydro (Lending)**
   - Type: Lending protocol
   - Risk Level: Low
   - Expected APY: ~3-5%
   - Use Case: Stable, predictable yield

2. **Velodrome (LP)**
   - Type: Liquidity provision
   - Risk Level: Higher
   - Expected APY: 20-50%+
   - Use Case: Higher yield with increased risk

### Strategy Characteristics

**Tydro (Lending)**:
- ✅ Low risk
- ✅ Stable yield
- ✅ Liquid (can withdraw anytime)
- ✅ Receipt tokens (aTokens)

**Velodrome (LP)**:
- ✅ Higher yield potential
- ✅ VELO token rewards (Velodrome's native reward token)
- ✅ Zap utility support for easy LP operations
- ⚠️ Impermanent loss risk
- ⚠️ Requires LP position management
- ⚠️ Less liquid

---

## Smart Allocation

### YieldAllocator Contract

The `YieldAllocator` contract enables dynamic strategy allocation:

```solidity
contract YieldAllocator {
    mapping(uint8 => IYieldStrategy) public strategies;
    
    function allocateFunds(address token, uint256 amount, uint8 forceStrategy) {
        // Auto-select best strategy based on APY
        // Or force allocation to specific strategy
    }
}
```

### Allocation Modes

1. **Auto-Allocation**: Automatically selects best strategy based on:
   - Current APY rates
   - Risk tolerance
   - Token characteristics
   - Available liquidity

2. **Forced Allocation**: Manually specify strategy:
   - Use `forceStrategy` parameter
   - Override auto-selection
   - Useful for specific requirements

### Allocation Logic

```solidity
if (forceStrategy != 0) {
    // Use specified strategy
    strategies[forceStrategy].deposit(token, amount);
} else {
    // Auto-select based on APY
    uint8 bestStrategy = selectBestStrategy(token);
    strategies[bestStrategy].deposit(token, amount);
}
```

---

## Compounding Strategy

### Yield Split

Yield can be split between two paths:

- **Compound**: Re-deposit to increase principal
- **Bridge**: Send back to L1 for withdrawal

### Default Configuration

Default: **50% compound, 50% bridge** (configurable per harvest)

### Compounding Flow

```solidity
function harvestAndBridge(address token, uint8 compoundPercent) {
    // 1. Withdraw yield from strategies
    uint256 yield = withdrawYield(token);
    
    // 2. Calculate split
    uint256 compoundAmount = yield * compoundPercent / 100;
    uint256 bridgeAmount = yield - compoundAmount;
    
    // 3. Re-deposit compound portion
    depositToStrategy(token, compoundAmount);
    
    // 4. Bridge remaining portion
    bridgeToL1(token, bridgeAmount);
}
```

### Benefits

- **Compound Portion**: Increases principal, leading to exponential growth
- **Bridge Portion**: Provides liquidity for users to withdraw yield
- **Flexible**: Adjustable per harvest based on needs

---

## Strategy Management

### Deposit to Strategy

**Tydro**:
```solidity
function depositToTydro(address token, uint256 amount) {
    // Transfer tokens to Tydro
    // Receive aTokens as receipt
    // Update tokenStatus
}
```

**Velodrome**:
```solidity
function deployToVelodrome(LPParams memory params) {
    // Use zap utility to swap tokens if needed
    // Create LP position via zap utility
    // Add liquidity to pool
    // Receive LP tokens
    // Optionally stake LP tokens for VELO rewards
    // Update tokenStatus
}
```

**Zap Utility Integration**:
- One-click zap and add LP simplifies Velodrome operations
- Automatic token swapping to optimal ratios
- Seamless LP position creation

### Withdrawal from Strategy

**Tydro**:
- Direct withdrawal via Tydro interface
- Receive underlying tokens
- Update balances

**Velodrome**:
- Remove liquidity from pool
- Receive underlying tokens
- Handle potential impermanent loss

---

## Yield Calculation

### Available Yield

```solidity
yieldAvailable = currentBalance - depositedAmount
```

### Yield Sources

1. **Lending Yield**: Interest accrued on lent tokens (Tydro)
2. **LP Rewards**: Trading fees and incentives from liquidity pools (Velodrome)
3. **VELO Rewards**: Velodrome's native reward token earned through LP staking
4. **Compounding**: Previously compounded yield generating additional yield

### Yield Tracking

- **depositedAmount**: Original principal
- **currentBalance**: Current total (principal + yield)
- **yieldAvailable**: Harvestable yield

---

## Multi-Strategy Support

### Simultaneous Strategies

The vault can deploy to multiple strategies simultaneously:
- Split allocation across strategies
- Diversify risk
- Optimize returns

### Strategy Switching

- Can migrate between strategies
- Rebalance allocations
- Adjust based on market conditions

---

## Related Documentation

- [Version History](./versions.md) - V1 vs V2 strategy support comparison
- [Contract Mechanics](./contracts.md) - Strategy-related contract functions and zap utilities
- [User Flows](./user-flows.md) - How strategies are used in flows
- [Storage Layout](./storage.md) - Strategy state tracking

