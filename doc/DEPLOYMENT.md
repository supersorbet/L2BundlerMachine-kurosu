# Deployment Quick Reference

## Prerequisites

1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. Set up environment variables in `.env`:
   ```bash
   PRIVATE_KEY=your_key
   ETH_RPC=https://eth.llamarpc.com
   INK_RPC=https://rpc-gel.inkonchain.com
   ```

## Deployment Order

### 1. Deploy L2 Vault (Ink)

```bash
export L1_RECIPIENT=0x... # Your L1 address or L1 depositor

forge script script/DeployL2.s.sol:DeployL2 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast

export L2_VAULT=0x... # Save this!
```

**Fund with gas:**
```bash
cast send $L2_VAULT --value 0.1ether \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### 2. Deploy L1 Depositor (Ethereum)

```bash
forge script script/DeployL1.s.sol:DeployL1 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast

export L1_DEPOSITOR=0x... # Save this!
```

### 3. Configure Mappings

**On L1:**
```bash
cast send $L1_DEPOSITOR \
    "setTokenMapping(address,address)" \
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \  # USDT L1
    $USDT0_L2 \                                    # USDT0 L2 (from Ink docs)
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

**On L2:**
```bash
# Set mapping
cast send $L2_VAULT \
    "setTokenMapping(address,address)" \
    $USDT0_L2 \
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY

# Set L1 recipient
cast send $L2_VAULT \
    "setL1Recipient(address)" \
    $L1_DEPOSITOR \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

## Testing Flow

1. **Approve & Deposit**: `depositToL2(USDT, 10_000_000, 9_950_000)`
2. **Wait for bridge**: ~2-3 seconds
3. **Deposit to Tydro**: `deposit(USDT0, amount)` on L2
4. **Wait for yield**: 24-48 hours
5. **Harvest**: `harvestAndBridge(USDT0, 50)` - 50% compound, 50% bridge
6. **Withdraw**: `withdrawYield(USDT)` on L1

## Addresses Needed

Before deployment, gather these from documentation:

- [ ] Tydro Pool address (Ink)
- [ ] Across SpokePool address (Ink)
- [ ] USDT0 address (Ink L2 token)

## Verification

After deployment, verify contracts on:
- Ethereum: [Etherscan](https://etherscan.io)
- Ink: [Ink Explorer](https://explorer.inkonchain.com)

