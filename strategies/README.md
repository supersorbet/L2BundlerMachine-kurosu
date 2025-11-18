# Yield Strategies

The system supports multiple yield strategies, allowing users to optimize returns based on risk tolerance and market conditions.

---

## 📊 Supported Strategies

### 1. Tydro (Lending)

**Type**: Money Market / Lending Protocol  
**Risk Level**: Low  
**APY Range**: 3-5% (varies by token)  
**Strategy ID**: 1

#### Overview

Tydro is an AAVE V3 fork on Ink L2, providing overcollateralized lending. Users deposit tokens and earn interest from borrowers.

#### How It Works

```solidity
// Deposit to Tydro
bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(
    token,
    amount,
    0  // Referral code
);
IL2Pool(TYDRO_POOL).supply(supplyArgs);

// Receive aTokens (1:1 with deposited amount)
// aTokens accrue interest over time
```

#### Yield Generation

- **Interest Rate**: Variable rate based on utilization
- **Compounding**: Automatic via aToken appreciation
- **Liquidity**: High (can withdraw anytime)

#### Code Example

```solidity
// Deposit 10,000 USDT to Tydro
vault.depositToTydro(usdt0, 10_000_000_000);

// Check yield after some time
uint256 yield = vault.getYieldAvailable(usdt0);

// Harvest yield (50% compound, 50% bridge)
vault.harvestAndBridge(usdt0, 50);
```

#### Advantages

- ✅ Low risk (overcollateralized)
- ✅ High liquidity
- ✅ Stable returns
- ✅ No impermanent loss

#### Considerations

- ⚠️ Lower APY compared to LP strategies
- ⚠️ Interest rates vary with market conditions

---

### 2. Velodrome (Liquidity Provision)

**Type**: DEX Liquidity Pool  
**Risk Level**: Medium  
**APY Range**: 20-50%+ (varies by pool)  
**Strategy ID**: 2

#### Overview

Velodrome is a DEX on Ink L2 (similar to Uniswap V2). Users provide liquidity to trading pairs and earn fees from trades.

#### How It Works

```solidity
struct LPParams {
    address tokenA;
    address tokenB;
    uint256 amountA;
    uint256 amountB;
    bool stable;        // Stable or volatile pair
    bool stakeInGauge;  // Stake LP tokens for additional rewards
}

// Deploy to Velodrome
vault.deployToVelodrome(LPParams({
    tokenA: usdt0,
    tokenB: usdc0,
    amountA: 5_000_000_000,
    amountB: 5_000_000_000,
    stable: true,
    stakeInGauge: true
}));
```

#### Yield Generation

- **Trading Fees**: Earn fees from swaps (typically 0.01% or 0.05%)
- **VELO Emissions**: Additional rewards for staking in gauge
- **Volume-Based**: Higher volume = higher yield

#### Code Example

```solidity
// Deploy to USDT/USDC stable pair
vault.deployToVelodrome(LPParams({
    tokenA: usdt0,
    tokenB: usdc0,
    amountA: 5_000_000_000,  // 5,000 USDT
    amountB: 5_000_000_000,    // 5,000 USDC
    stable: true,             // Stable pair
    stakeInGauge: true        // Stake for VELO rewards
}));
```

#### Advantages

- ✅ Higher APY potential
- ✅ VELO token rewards
- ✅ Supports both stable and volatile pairs

#### Considerations

- ⚠️ Impermanent loss risk
- ⚠️ Higher complexity
- ⚠️ Requires two tokens for LP

---

## 🧠 Smart Allocation

### YieldAllocator

The `YieldAllocator` contract enables automatic allocation across strategies based on APY.

#### How It Works

```solidity
// Register strategies
allocator.registerStrategy(tydroStrategy);    // Strategy ID: 1
allocator.registerStrategy(velodromeStrategy); // Strategy ID: 2

// Auto-allocate funds
allocator.allocateFunds(usdt0, 10_000_000_000, 0);
// 0 = auto-select best strategy based on APY
```

#### Allocation Logic

1. **Query APYs**: Get current APY for each strategy
2. **Compare**: Select strategy with highest APY
3. **Respect Limits**: Check max allocation per strategy
4. **Allocate**: Deposit to selected strategy

#### Rebalancing

Automatically rebalance when yield differential exceeds threshold:

```solidity
// Rebalance if APY difference > 5%
allocator.rebalance(usdt0, 1, 2, amount);
// Move from Tydro (1) to Velodrome (2)
```

---

## 📈 Strategy Comparison

| Feature | Tydro | Velodrome | Curve Finance (Planned) |
|---------|-------|-----------|------------------------|
| **APY** | 3-5% | 20-50%+ | 5-15%+ |
| **Risk** | Low | Medium | Low-Medium |
| **Liquidity** | High | Medium | Very High |
| **Impermanent Loss** | None | Possible | Minimal (stablecoins) |
| **Complexity** | Low | Medium | Low |
| **Token Requirements** | 1 | 2 | 2-4 (stablecoins) |
| **Compounding** | Automatic | Manual | Manual |
| **Status** | ✅ Live | ✅ Live | 🚧 Priority Roadmap |

---

## 💡 Best Practices

### Diversification

Consider splitting funds across strategies:

```solidity
// 70% to Tydro (low risk)
vault.depositToTydro(usdt0, 7_000_000_000);

// 30% to Velodrome (higher yield)
vault.deployToVelodrome(LPParams({
    tokenA: usdt0,
    tokenB: usdc0,
    amountA: 1_500_000_000,
    amountB: 1_500_000_000,
    stable: true,
    stakeInGauge: true
}));
```

### Regular Harvesting

Harvest yield regularly to compound or bridge:

```solidity
// Harvest weekly with 50/50 split
vault.harvestAndBridge(usdt0, 50);
// 50% compounds, 50% bridges to L1
```

### Monitoring

Monitor strategy performance:

```solidity
// Check Tydro yield
uint256 tydroYield = vault.getYieldAvailable(usdt0);

// Check Velodrome fees (via helper)
uint256 veloFees = veloHelper.getClaimableFees(pair);
```

---

## 🔧 Strategy Configuration

### Tydro Settings

```solidity
// No special configuration needed
// Just deposit and earn interest
```

### Velodrome Settings

```solidity
// Choose pair type
bool stable = true;  // Stable pair (lower risk)
bool stable = false; // Volatile pair (higher risk, higher yield)

// Choose whether to stake
bool stakeInGauge = true;  // Stake for VELO rewards
```

### Allocation Settings

```solidity
// Set max allocation per strategy
allocator.setMaxAllocation(1, 7000);  // Max 70% to Tydro
allocator.setMaxAllocation(2, 3000);  // Max 30% to Velodrome

// Set rebalance threshold
allocator.setRebalanceThreshold(500);  // 5% APY difference
```

---

## 📊 Yield Calculation

### Tydro Yield

```solidity
// Yield = current aToken balance - deposited amount
uint256 yield = aToken.balanceOf(vault) - depositedAmount;
```

### Velodrome Yield

```solidity
// Yield = claimable fees + VELO rewards
uint256 fees = pair.claimableFeesToken0();
uint256 veloRewards = gauge.claimableRewards(vault);
uint256 totalYield = fees + veloRewards;
```

---

## 🚀 Future: Velodrome Automation Integration

### Planned Enhancements

With additional resources, we plan to integrate advanced Velodrome automation patterns inspired by [Velodrome's automation repository](https://github.com/velodrome-finance/automations/tree/main/scripts).

#### Automated LP Management

**Current State**: Manual LP position management  
**Future State**: Fully automated LP optimization

**Planned Features**:
- ✅ **Auto-Compounding**: Automatically compound trading fees back into LP
- ✅ **VELO Reward Harvesting**: Auto-harvest and stake VELO rewards
- ✅ **Position Rebalancing**: Auto-rebalance LP positions to maintain ratios
- ✅ **Impermanent Loss Monitoring**: Alert and mitigate IL when detected
- ✅ **Fee Optimization**: Auto-select optimal fee tier (0.01% vs 0.05%)

**Example Implementation**:
```solidity
// Future: Automated LP management
function autoManageVelodromeLP(address tokenA, address tokenB) external {
    // 1. Check accumulated fees
    uint256 fees = getAccumulatedFees(tokenA, tokenB);
    if (fees > threshold) {
        // Auto-compound fees
        compoundVelodromeFees(tokenA, tokenB);
    }
    
    // 2. Check VELO rewards
    uint256 veloRewards = getVelodromeRewards(tokenA, tokenB);
    if (veloRewards > threshold) {
        // Auto-harvest and stake
        harvestAndStakeVelodromeRewards(tokenA, tokenB);
    }
    
    // 3. Monitor impermanent loss
    if (impermanentLossExceeded(tokenA, tokenB)) {
        // Alert or auto-rebalance
        rebalanceVelodromePosition(tokenA, tokenB);
    }
}
```

#### Gauge Staking Automation

**Current State**: Manual gauge staking  
**Future State**: Automatic gauge management

**Planned Features**:
- Auto-stake LP tokens in gauges
- Auto-claim VELO rewards
- Auto-compound VELO rewards
- Optimal gauge selection

#### Multi-Pool Optimization

**Current State**: Single pool deployment  
**Future State**: Dynamic pool selection

**Planned Features**:
- Monitor multiple pools for same pair
- Auto-select pool with highest APY
- Auto-migrate between pools when beneficial
- Volume-based pool selection

### Benefits of Automation

1. **Hands-Free Operation**: Set it and forget it
2. **Optimized Yields**: Always in the best pools
3. **Reduced Gas**: Batch operations save gas
4. **Risk Management**: Automatic IL monitoring
5. **Time Savings**: No manual intervention needed

### Integration with Decentralized Keepers

These automation features will be powered by a decentralized keeper network:

- **Permissionless**: Anyone can run a keeper
- **Incentivized**: Keepers earn fees for operations
- **Redundant**: Multiple keepers ensure uptime
- **Transparent**: All operations on-chain

See [Future Roadmap](./../ROADMAP.md) for complete automation plans.

---

## 🔗 Related Documentation

- [Core Contracts](./../contracts/README.md)
- [Architecture Overview](./../architecture/README.md)
- [User Guide](./../user-guide/README.md)
- [Future Roadmap](./../ROADMAP.md)

