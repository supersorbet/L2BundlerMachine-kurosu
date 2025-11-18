# Bridge Architecture

## Overview

The L1-L2 Ink Yield Bundler uses **Across Protocol** for secure, efficient cross-chain token transfers between Ethereum Mainnet and Ink L2.

---

## Across Protocol Integration

### Protocol Components

- **HubPool** (L1): Central liquidity pool and deposit coordinator
- **SpokePool** (L2): Destination chain pool that receives deposits
- **Relayers**: Network of relayers that fill deposits on destination chains

### Why Across Protocol?

- ✅ Fast finality (typically minutes)
- ✅ Low fees compared to native bridges
- ✅ Support for arbitrary tokens
- ✅ Reliable relay network
- ✅ Slippage protection

---

## L1 → L2 Bridge (Deposits)

### Bridge Initiation

When users deposit tokens, L1Depositor bridges them to L2:

```solidity
IHubPool(HUB_POOL).deposit(
    l2Token,              // Destination token address
    l2Vault,              // Recipient on L2
    amount,               // Amount to bridge
    DESTINATION_CHAIN_ID  // Ink L2 chain ID
);
```

### Parameters

- **l2Token**: The L2 token address (mapped from L1 token)
- **l2Vault**: The BundledYieldVaultV2 contract address on L2
- **amount**: Token amount to bridge
- **DESTINATION_CHAIN_ID**: Ink L2 chain ID (configured constant)

### Flow

1. **User Deposit**: Owner calls `depositToL2()` on L1Depositor
2. **Token Transfer**: Tokens are transferred to L1Depositor
3. **Bridge Call**: L1Depositor calls HubPool.deposit()
4. **Relayer Fills**: Across relayers fill the deposit on L2
5. **Tokens Arrive**: L2Vault receives tokens via Across callback
6. **Auto-Processing**: L2Vault can auto-deposit to strategies

---

## L2 → L1 Bridge (Yield)

### Bridge Initiation

When yield is harvested, L2Vault bridges it back to L1:

```solidity
ISpokePool(ACROSS_SPOKE_POOL).deposit(
    l1Recipient,          // Recipient on L1 (L1Depositor)
    l1Token,              // L1 token address
    amount,               // Amount to bridge
    L1_CHAIN_ID,          // Ethereum chain ID
    defaultSlippageBps    // Slippage tolerance
);
```

### Parameters

- **l1Recipient**: The L1Depositor contract address
- **l1Token**: The L1 token address (mapped from L2 token)
- **amount**: Yield amount to bridge
- **L1_CHAIN_ID**: Ethereum Mainnet chain ID (1)
- **defaultSlippageBps**: Maximum acceptable slippage

### Flow

1. **Harvest Trigger**: Keeper calls `harvestAndBridge()` on L2Vault
2. **Yield Withdrawal**: L2Vault withdraws yield from strategies
3. **Split Strategy**: Yield is split (compound vs bridge)
4. **Bridge Call**: L2Vault calls SpokePool.deposit() for bridge portion
5. **Relayer Fills**: Across relayers fill the deposit on L1
6. **Yield Arrives**: L1Depositor receives yield tokens
7. **Balance Update**: L1Depositor updates `yieldBalance` mapping

---

## Bridge Flow Details

### 1. Initiate Bridge

Contract calls bridge deposit function with:
- Destination chain ID
- Recipient address
- Token address
- Amount
- Slippage tolerance

### 2. Relayer Fills

Across relayers monitor deposits and fill them on destination chain:
- Relayers provide liquidity
- Users pay relayer fees
- Fast finality (typically 2-10 minutes)

### 3. Tokens Arrive

Recipient contract receives tokens on destination chain:
- Tokens arrive via Across callback
- Contract can process automatically
- Balance updates accordingly

### 4. Callback Processing

Optional callback for automatic processing:
- L2Vault can auto-deposit bridged tokens
- L1Depositor can auto-update yield balances
- Reduces manual intervention

---

## Slippage Protection

### Configuration

- **maxSlippageBps**: Maximum acceptable slippage (basis points)
- Configurable per token or globally
- Validates minimum amounts in bridge operations

### Protection Mechanisms

- Minimum amount validation
- Slippage tolerance checks
- Revert on unfavorable rates
- Configurable per operation

---

## Bridge Security

### Validation

- Recipient address verification
- Token address mapping validation
- Amount consistency checks
- Chain ID verification

### Error Handling

- Reverts on invalid parameters
- Handles bridge failures gracefully
- Tracks failed bridge attempts
- Allows retry mechanisms

---

## Gas Optimization

### Bridge Efficiency

- Single transaction initiates bridge
- No intermediate steps required
- Minimal gas overhead
- Efficient Across Protocol integration

---

## Related Documentation

- [User Flows](./user-flows.md) - How bridges are used in deposit and harvest flows
- [Contract Responsibilities](./contracts.md) - Bridge functions in contracts
- [Security Architecture](./security.md) - Bridge security considerations

