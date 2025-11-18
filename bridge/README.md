# Bridge Integration

## Overview

The system uses **Across Protocol** for cross-chain bridging between Ethereum L1 and Ink L2. Across provides fast, secure, and cost-effective bridging with \~2-3 second finality.

***

## 🌉 Across Protocol

### What is Across?

Across Protocol is a cross-chain bridge that uses a **unified liquidity pool** model. It provides:

* ✅ **Fast Finality**: \~2-3 seconds
* ✅ **Low Fees**: Competitive bridge fees
* ✅ **High Security**: Audited and battle-tested
* ✅ **Intent-Based**: Relayer fills deposits

### How It Works

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│  Ethereum   │         │   Across     │         │    Ink L2   │
│     L1      │         │   HubPool    │         │             │
│             │         │              │         │             │
│ L1Depositor │────────▶│  Liquidity   │────────▶│ L2 Vault    │
│             │         │    Pool      │         │             │
└─────────────┘         └──────────────┘         └─────────────┘
                              │
                              │ Relayers fill deposits
                              ▼
```

***

## 🔄 Bridge Flow

### L1 → L2 (Deposits)

#### Step 1: Initiate Deposit

```solidity
// In L1Depositor
IHubPool(HUB_POOL).deposit(
    l2Vault,              // Recipient on L2
    usdt,                 // Input token (L1)
    usdt0,                // Output token (L2)
    amount,               // Amount to bridge
    minAmount,            // Minimum amount (slippage)
    DESTINATION_CHAIN_ID, // Ink L2 chain ID
    address(0),           // Exclusive relayer (none)
    block.timestamp,      // Quote timestamp
    message               // Optional message
);
```

#### Step 2: Relayer Fills

Across relayers monitor deposits and fill them on the destination chain:

* Relayers provide liquidity
* They earn fees for filling
* Fills happen within seconds

#### Step 3: Tokens Arrive

Tokens arrive at the L2 vault:

```solidity
// Tokens are automatically received
// Vault can detect new balance and auto-deposit
```

### L2 → L1 (Yield)

#### Step 1: Initiate Bridge

```solidity
// In L2 Vault
ISpokePool(ACROSS_SPOKE_POOL).deposit(
    l1Recipient,          // Recipient on L1
    l1Token,              // L1 token address
    amount,               // Amount to bridge
    L1_CHAIN_ID,          // Ethereum chain ID (1)
    defaultSlippageBps    // Slippage tolerance
);
```

#### Step 2: Relayer Fills

Relayers fill the deposit on L1:

* They provide liquidity from HubPool
* They earn fees
* Fills happen within seconds

#### Step 3: Yield Arrives

Yield arrives at L1Depositor:

```solidity
// Yield is tracked in yieldBalance
yieldBalance[token] += amount;
```

***

## 🔧 Bridge Configuration

### Token Mappings

Tokens must be mapped on both chains:

#### L1 Mapping

```solidity
// Map L1 token to L2 token
l1Depositor.setTokenMapping(
    0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT L1
    0x... // USDT0 L2
);
```

#### L2 Mapping

```solidity
// Map L2 token to L1 token
vault.setTokenMapping(
    0x..., // USDT0 L2
    0xdAC17F958D2ee523a2206206994597C13D831ec7  // USDT L1
);
```

### Slippage Protection

Configure maximum slippage tolerance:

```solidity
// On L1
l1Depositor.setMaxSlippage(50);  // 0.5% max slippage

// On L2
vault.setDefaultSlippageBps(200);  // 2% default slippage
```

### Chain IDs

* **Ethereum Mainnet**: `1`
* **Ink L2**: `57073`



***

## 💰 Bridge Fees

### Fee Structure

Across charges fees for bridging:

* **Deposit Fee**: Small fee on deposit
* **Relayer Fee**: Fee paid to relayers
* **Total**: Typically \~0.1-0.2% of amount

### Fee Calculation

Fees are calculated by Across based on:

* Token liquidity
* Destination chain
* Current market conditions

### Minimizing Fees

* **Batch Operations**: Bridge larger amounts
* **Timing**: Bridge during low congestion
* **Token Selection**: Some tokens have lower fees

***

## 🛡️ Security Considerations

### Bridge Security

* ✅ **Audited Protocol**: Across is audited
* ✅ **Unified Liquidity**: Single pool model
* ✅ **Relayer Network**: Decentralized relayers
* ✅ **Slippage Protection**: Configurable limits

### Best Practices

1. **Verify Mappings**: Always verify token mappings
2. **Check Slippage**: Use appropriate slippage tolerance
3. **Monitor Transactions**: Track bridge status
4. **Test First**: Test on testnet before mainnet

***

## 📊 Bridge Status Monitoring

### Check Bridge Status

Use Across's explorer to check transaction status:

```
https://across.to/transactions/<tx-hash>
```

### On-Chain Verification

```solidity
// Check if tokens arrived on L2
uint256 balance = IERC20(usdt0).balanceOf(vault);

// Check if yield arrived on L1
uint256 yield = l1Depositor.yieldBalance(usdt);
```

***

## 🔄 Alternative Bridge Options

### Relay Protocol (Future)

The system also supports Relay Protocol integration:

```solidity
// Alternative bridge implementation
// Uses Relay Depository for L1-L2 transfers
// Optimized for Ink L2 specifically
```

### Native Bridge (Not Available)

Ink L2 does not support native OP Stack bridge:

* Uses Relay Protocol instead
* Across is the primary bridge solution

***

## 🚨 Troubleshooting

### Bridge Doesn't Complete

**Symptoms**: Tokens don't arrive on destination chain

**Solutions**:

1. Check transaction on Across explorer
2. Verify token mappings are correct
3. Check if relayer filled the deposit
4. Contact Across support if needed

### High Slippage

**Symptoms**: Received amount is less than expected

**Solutions**:

1. Increase slippage tolerance
2. Bridge during lower congestion
3. Check token liquidity on Across

***

## 📚 Additional Resources

* [Across Protocol Docs](https://docs.across.to/)
* [Across Explorer](https://across.to/)
* [Ink L2 Documentation](https://inkonchain.com/docs)

***

## 🔗 Related Documentation

* [Architecture Overview](../architecture/)
* [Core Contracts](../contracts/)
* [User Guide](../user-guide/)
* [Deployment Guide](broken-reference)
