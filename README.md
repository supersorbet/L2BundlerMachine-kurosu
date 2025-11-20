# L1-L2 Yield Aggregator

A production-ready cross-chain yield aggregator system that bridges assets from Ethereum L1 to Ink L2, farms yield on Tydro & Velodrome pools, and bridges yield back to L1.

## 🏗️ Architecture

The system consists of two main contracts:

1. **L1DepositorV2_PRODUCTION.sol** - Deployed on Ethereum Mainnet
   - Handles deposits from users
   - Bridges tokens to Ink L2 via Across Bridge
   - Receives and manages yield from L2
   - Token mapping (L1 tokens → L2 tokens)

2. **BundledYieldVaultV2_PRODUCTION.sol** - Deployed on Ink L2
   - Receives bridged tokens
   - Deposits to Tydro pools for yield farming
   - Harvests yield periodically
   - Bridges yield back to L1 (via Across)
   - Supports yield compounding

## 📋 Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Private key with ETH for gas (on both L1 and L2)
- Access to Ink L2 network
- Across Bridge configured addresses

## 🚀 Quick Start

### 1. Install Dependencies

```bash
forge install
```

### 2. Set Environment Variables

Create a `.env` file:

```bash
PRIVATE_KEY=your_private_key_here
ETH_RPC=https://eth.llamarpc.com
INK_RPC=https://rpc-gel.inkonchain.com

# Set these after deployment
L1_DEPOSITOR=0x...
L2_VAULT=0x...
USDT0_L2=0x...  # USDT0 address on Ink
```

### 3. Deploy Contracts

#### Deploy L2 Vault First (Ink L2)

```bash
# Set L1 recipient (your wallet or L1 depositor address)
export L1_RECIPIENT=0x...

# Deploy on Ink L2
forge script script/DeployL2.s.sol:DeployL2 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# Save the deployed address
export L2_VAULT=0x...
```

#### Fund L2 Vault with Gas

```bash
cast send $L2_VAULT \
    --value 0.1ether \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

#### Deploy L1 Depositor (Ethereum)

```bash
# Make sure L2_VAULT is set
forge script script/DeployL1.s.sol:DeployL1 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# Save the deployed address
export L1_DEPOSITOR=0x...
```

### 4. Configure Contracts

#### On L1 (Set Token Mapping)

```bash
# Using cast
cast send $L1_DEPOSITOR \
    "setTokenMapping(address,address)" \
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \  # USDT L1
    $USDT0_L2 \                                    # USDT0 L2
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

#### On L2 (Set Token Mapping & L1 Recipient)

```bash
# Set token mapping
cast send $L2_VAULT \
    "setTokenMapping(address,address)" \
    $USDT0_L2 \                                    # USDT0 L2
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \  # USDT L1
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY

# Set L1 recipient
cast send $L2_VAULT \
    "setL1Recipient(address)" \
    $L1_DEPOSITOR \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

Or use the setup script:

```bash
forge script script/Setup.s.sol:Setup \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast
```

## 🧪 Testing with $10 USDT

### Step 1: Approve USDT on L1

```bash
# Approve L1Depositor to spend USDT
cast send 0xdAC17F958D2ee523a2206206994597C13D831ec7 \
    "approve(address,uint256)" \
    $L1_DEPOSITOR \
    10000000 \  # $10 USDT (6 decimals)
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

### Step 2: Deposit to L2

```bash
cast send $L1_DEPOSITOR \
    "depositToL2(address,uint256,uint256)" \
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \  # USDT
    10000000 \                                      # $10
    9950000 \                                       # Min amount (0.5% slippage)
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

### Step 3: Verify on L2

```bash
# Check L2Vault balance
cast call $USDT0_L2 \
    "balanceOf(address)(uint256)" \
    $L2_VAULT \
    --rpc-url $INK_RPC
```

### Step 4: Deposit to Tydro Pool

```bash
cast send $L2_VAULT \
    "deposit(address,uint256)" \
    $USDT0_L2 \
    9990000 \  # Amount received after bridge fee
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### Step 5: Wait for Yield (24-48 hours)

Check yield available:

```bash
cast call $L2_VAULT \
    "getYieldAvailable(address)(uint256)" \
    $USDT0_L2 \
    --rpc-url $INK_RPC
```

### Step 6: Harvest Yield

Harvest and bridge yield back to L1 (50% compound, 50% bridge):

```bash
cast send $L2_VAULT \
    "harvestAndBridge(address,uint8)" \
    $USDT0_L2 \
    50 \  # 50% compound, 50% bridge
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### Step 7: Withdraw Yield on L1

```bash
cast send $L1_DEPOSITOR \
    "withdrawYield(address)" \
    0xdAC17F958D2ee523a2206206994597C13D831ec7 \  # USDT
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

## 📊 Expected Results

With $10 USDT @ 3% APY:

- **Start**: $10.00
- **After 48h**: $10.0054
- **Harvest (50/50 split)**:
  - Compound: $0.0027 → stays on L2
  - Bridge: $0.0027 → goes to L1
- **After harvest**:
  - L2 Balance: $10.0027 (original + compound)
  - L1 Profit: $0.0027 (in your wallet)

## 🔧 Configuration

### Important Addresses

**Ethereum Mainnet:**
- USDT: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- Across HubPool: `0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5`

**Ink L2:**
- USDT0: (Check Ink documentation)
- Tydro Pool: (Check Ink/Tydro documentation)
- Across SpokePool: (Check Across documentation)

### Contract Settings

**L1Depositor:**
- Max slippage: 0.5% (50 bps) - adjustable
- Min deposit: 1000 tokens - adjustable

**L2Vault:**
- Min gas balance: 0.05 ETH - adjustable
- Compound percentage: 0-100% - per harvest

## 🛡️ Security Features

- ✅ Emergency pause functionality
- ✅ Slippage protection
- ✅ Reentrancy guards
- ✅ Access control (Ownable)
- ✅ Token mapping verification
- ✅ Minimum deposit protection

## 🆘 Troubleshooting

### "Token not supported"
→ Did you call `setTokenMapping()` on both L1 and L2?

### "L2 token not set"
→ Call `setTokenMapping()` with correct addresses

### "Low gas"
→ Send more ETH to L2Vault: `cast send $L2_VAULT --value 0.1ether`

### "No yield"
→ Wait longer (24-48h minimum)

### "Bridge doesn't complete"
→ Check [Across transactions](https://across.to/transactions) with your tx hash

## 📝 Contract Functions

### L1DepositorV2_PRODUCTION

- `depositToL2(token, amount, minAmount)` - Deposit tokens to L2
- `setTokenMapping(l1Token, l2Token)` - Map L1 token to L2 token
- `setL2Vault(vault)` - Set L2 vault address
- `withdrawYield(token)` - Withdraw accumulated yield
- `pause()` / `unpause()` - Emergency pause

### BundledYieldVaultV2_PRODUCTION

- `deposit(token, amount)` - Deposit tokens to Tydro pool
- `harvestAndBridge(token, compoundPercent)` - Harvest and bridge yield
- `getStatus(token)` - Get token status
- `getYieldAvailable(token)` - Check available yield
- `setTokenMapping(l2Token, l1Token)` - Map L2 token to L1 token
- `setL1Recipient(recipient)` - Set L1 recipient
- `refillGas()` - Refill gas balance (payable)
- `pause()` / `unpause()` - Emergency pause

## 🧪 Development

### Compile

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Lint

```bash
forge test --gas-report
```

## 📚 Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [Across Protocol](https://docs.across.to/)
- [Ink Network](https://inkonchain.com/docs)

## ⚠️ Important Notes

1. **Token Mapping**: Must be set on both L1 and L2 contracts
2. **Gas Management**: L2 vault needs ETH for gas (minimum 0.05 ETH recommended)
3. **Slippage**: Default max slippage is 0.5% - adjust based on market conditions
4. **Yield Timing**: Wait 24-48 hours minimum before expecting yield
5. **Bridge Fees**: Both deposits and yield bridging incur Across bridge fees (~0.1%)

## 📄 License

MIT

---

**Ready to farm yield across chains! 🌾✨**
