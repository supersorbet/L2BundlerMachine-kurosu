# Deployment Guide

Complete guide for deploying the L1-L2 Cross-Chain Yield Aggregator system.

---

## 📋 Prerequisites

### Required Tools

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Private key with ETH for gas (on both L1 and L2)
- Access to Ink L2 network
- Environment variables configured

### Required Addresses

Before deployment, gather these addresses:

- [ ] Tydro Pool address (Ink L2)
- [ ] L2 Encoder address (Ink L2)
- [ ] Across HubPool address (Ethereum L1)
- [ ] Across SpokePool address (Ink L2)
- [ ] Velodrome Router address (Ink L2)
- [ ] Token addresses (USDT L1, USDT0 L2)
- [ ] Ink L2 chain ID

---

## 🔧 Environment Setup

### Create `.env` File

```bash
# Private key (with or without 0x prefix)
PRIVATE_KEY=your_private_key_here

# RPC URLs
ETH_RPC=https://eth.llamarpc.com
INK_RPC=https://rpc-gel.inkonchain.com

# Contract addresses (set after deployment)
L1_DEPOSITOR=0x...
L2_VAULT=0x...
FACTORY=0x...

# Token addresses
USDT_L1=0xdAC17F958D2ee523a2206206994597C13D831ec7
USDT0_L2=0x...

# Infrastructure addresses
TYDRO_POOL=0x...
L2_ENCODER=0x...
ACROSS_HUB_POOL=0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5
ACROSS_SPOKE_POOL=0x...
VELO_ROUTER=0x...
INK_CHAIN_ID=...

# L1 Recipient (your wallet or L1 depositor)
L1_RECIPIENT=0x...
```

### Install Dependencies

```bash
# Install Foundry dependencies
forge install

# Install npm dependencies (if needed)
npm install
```

---

## 🚀 Deployment Steps

### Step 1: Deploy L2 Vault (Ink L2)

Deploy the L2 vault first:

```bash
# Set L1 recipient (can be updated later)
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

**What happens**:
- Deploys `BundledYieldVaultV2_PRODUCTION` on Ink L2
- Sets initial L1 recipient
- Configures immutable addresses (Tydro, Across, Velodrome)

### Step 2: Fund L2 Vault with Gas

Send ETH to the vault for gas:

```bash
cast send $L2_VAULT \
    --value 0.1ether \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### Step 3: Deploy L1 Depositor (Ethereum)

Deploy the L1 depositor:

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

**What happens**:
- Deploys `L1DepositorV2_PRODUCTION` on Ethereum
- Sets L2 vault address
- Configures Across HubPool

### Step 4: Configure Token Mappings

#### On L1

```bash
cast send $L1_DEPOSITOR \
    "setTokenMapping(address,address)" \
    $USDT_L1 \
    $USDT0_L2 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

#### On L2

```bash
# Set token mapping
cast send $L2_VAULT \
    "setTokenMapping(address,address)" \
    $USDT0_L2 \
    $USDT_L1 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY

# Set L1 recipient
cast send $L2_VAULT \
    "setL1Recipient(address)" \
    $L1_DEPOSITOR \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### Step 5: Deploy Factory (Optional)

If deploying the factory:

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

export FACTORY=0x...
```

---

## ✅ Verification

### Verify Contracts

After deployment, verify contracts on block explorers:

#### Ethereum (Etherscan)

```bash
forge verify-contract \
    $L1_DEPOSITOR \
    L1DepositorV2_PRODUCTION \
    --chain-id 1 \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

#### Ink L2 (Explorer)

```bash
# Check Ink explorer for verification process
# https://explorer.inkonchain.com
```

### Test Deployment

Run a test deposit:

```bash
# 1. Approve USDT
cast send $USDT_L1 \
    "approve(address,uint256)" \
    $L1_DEPOSITOR \
    10000000 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY

# 2. Deposit to L2
cast send $L1_DEPOSITOR \
    "depositToL2(address,uint256,uint256)" \
    $USDT_L1 \
    10000000 \
    9950000 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY

# 3. Check balance on L2
cast call $USDT0_L2 \
    "balanceOf(address)(uint256)" \
    $L2_VAULT \
    --rpc-url $INK_RPC
```

---

## 🔐 Post-Deployment Configuration

### Configure Settings

#### L1 Depositor

```bash
# Set max slippage (basis points)
cast send $L1_DEPOSITOR \
    "setMaxSlippage(uint64)" \
    50 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY

# Set minimum deposit
cast send $L1_DEPOSITOR \
    "setMinDepositAmount(uint128)" \
    1000 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY
```

#### L2 Vault

```bash
# Set default compound percent
cast send $L2_VAULT \
    "setDefaultCompoundPercent(uint8)" \
    50 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY

# Set minimum gas balance
cast send $L2_VAULT \
    "setMinGasBalance(uint128)" \
    69000000000000000 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

### Transfer Ownership (Optional)

Transfer ownership to Gnosis Safe:

```bash
# Transfer L1 depositor ownership
cast send $L1_DEPOSITOR \
    "transferOwnership(address)" \
    $GNOSIS_SAFE \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY

# Transfer L2 vault ownership
cast send $L2_VAULT \
    "transferOwnership(address)" \
    $GNOSIS_SAFE \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY
```

**Note**: New owner must accept ownership in Safe interface.

---

## 📊 Deployment Checklist

### Pre-Deployment

- [ ] Foundry installed and configured
- [ ] Environment variables set
- [ ] All required addresses gathered
- [ ] Private key has ETH on both chains
- [ ] Testnet testing completed

### Deployment

- [ ] L2 vault deployed
- [ ] L2 vault funded with gas
- [ ] L1 depositor deployed
- [ ] Token mappings configured
- [ ] L1 recipient set
- [ ] Factory deployed (if needed)

### Post-Deployment

- [ ] Contracts verified on explorers
- [ ] Test deposit completed
- [ ] Settings configured
- [ ] Ownership transferred (if needed)
- [ ] Monitoring set up

---

## 🧪 Testing Deployment

### Test Deposit Flow

```bash
# 1. Approve tokens
cast send $USDT_L1 "approve(address,uint256)" $L1_DEPOSITOR 10000000 \
    --rpc-url $ETH_RPC --private-key $PRIVATE_KEY

# 2. Deposit
cast send $L1_DEPOSITOR \
    "depositToL2(address,uint256,uint256)" \
    $USDT_L1 10000000 9950000 \
    --rpc-url $ETH_RPC --private-key $PRIVATE_KEY

# 3. Wait for bridge (~2-3 seconds)

# 4. Check L2 balance
cast call $USDT0_L2 "balanceOf(address)(uint256)" $L2_VAULT \
    --rpc-url $INK_RPC

# 5. Auto-deposit
cast send $L2_VAULT "depositAvailable(address)" $USDT0_L2 \
    --rpc-url $INK_RPC --private-key $PRIVATE_KEY
```

### Test Harvest Flow

```bash
# 1. Wait for yield (24-48 hours)

# 2. Check yield
cast call $L2_VAULT "getYieldAvailable(address)(uint256)" $USDT0_L2 \
    --rpc-url $INK_RPC

# 3. Harvest
cast send $L2_VAULT \
    "harvestAndBridge(address,uint8)" \
    $USDT0_L2 50 \
    --rpc-url $INK_RPC --private-key $PRIVATE_KEY

# 4. Wait for bridge (~2-3 seconds)

# 5. Check L1 yield balance
cast call $L1_DEPOSITOR "yieldBalance(address)(uint256)" $USDT_L1 \
    --rpc-url $ETH_RPC

# 6. Withdraw yield
cast send $L1_DEPOSITOR \
    "withdrawYield(address,address)" \
    $USDT_L1 $YOUR_ADDRESS \
    --rpc-url $ETH_RPC --private-key $PRIVATE_KEY
```

---

## 🚨 Troubleshooting

### Deployment Fails

**Issue**: Deployment transaction fails

**Solutions**:
- Check gas price and limits
- Verify all addresses are correct
- Ensure sufficient ETH balance
- Check network connectivity

### Token Mapping Errors

**Issue**: "Token not supported" error

**Solutions**:
- Verify mappings on both L1 and L2
- Check token addresses are correct
- Ensure mappings are set before deposits

### Bridge Issues

**Issue**: Tokens don't arrive on destination

**Solutions**:
- Check transaction on Across explorer
- Verify chain IDs are correct
- Check token mappings
- Verify recipient addresses

---

## 📚 Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Across Protocol Docs](https://docs.across.to/)
- [Ink L2 Documentation](https://inkonchain.com/docs)

---

## 🔗 Related Documentation

- [Architecture Overview](./../architecture/README.md)
- [Core Contracts](./../contracts/README.md)
- [User Guide](./../user-guide/README.md)
- [Factory Deployment](./../factory/README.md)

