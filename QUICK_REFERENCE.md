# Quick Reference Guide

Quick lookup guide for common operations and addresses.

---

## 🚀 Quick Start Commands

### Deploy L2 Vault

```bash
forge script script/DeployL2.s.sol:DeployL2 \
    --rpc-url $INK_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Deploy L1 Depositor

```bash
forge script script/DeployL1.s.sol:DeployL1 \
    --rpc-url $ETH_RPC \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Deploy Vault via Factory

```solidity
address vault = factory.deployVault(l1DepositorAddress);
```

---

## 💰 Common Operations

### Deposit to L2

```solidity
// Approve first
IERC20(usdt).approve(l1Depositor, amount);

// Deposit
l1Depositor.depositToL2(usdt, amount, minAmount);
```

### Auto-Deposit on L2

```solidity
vault.depositAvailable(usdt0, true);  // With smart allocation
vault.depositAvailable(usdt0, false); // To Tydro
```

### Harvest Yield

```solidity
vault.harvestAndBridge(usdt0, 50);  // 50% compound, 50% bridge
```

### Withdraw Yield

```solidity
l1Depositor.withdrawYield(usdt, recipient);
```

---

## 🔧 Configuration

### Set Token Mapping (L1)

```solidity
l1Depositor.setTokenMapping(usdtL1, usdt0L2);
```

### Set Token Mapping (L2)

```solidity
vault.setTokenMapping(usdt0L2, usdtL1);
```

### Set L1 Recipient

```solidity
vault.setL1Recipient(l1DepositorAddress);
```

### Transfer Ownership

```solidity
vault.transferOwnership(gnosisSafeAddress);
```

---

## 📊 Status Checks

### Check Vault Status

```solidity
(uint256 deposited, uint256 balance, uint256 yield, uint256 gas) = 
    vault.getStatus(token);
```

### Check Yield Available

```solidity
uint256 yield = vault.getYieldAvailable(token);
```

### Check L1 Yield Balance

```solidity
uint256 yield = l1Depositor.yieldBalance(token);
```

---

## 🏭 Factory Operations

### Deploy Vault

```solidity
address vault = factory.deployVault(l1Recipient);
```

### Get Your Vaults

```solidity
address[] memory vaults = factory.getVaultsForOwner(owner);
```

### Get All Vaults

```solidity
address[] memory allVaults = factory.getAllVaults();
```

---

## 🌾 Yield Strategies

### Deposit to Tydro

```solidity
vault.depositToTydro(token, amount);
```

### Deploy to Velodrome

```solidity
vault.deployToVelodrome(LPParams({
    tokenA: usdt0,
    tokenB: usdc0,
    amountA: amountA,
    amountB: amountB,
    stable: true,
    stakeInGauge: true
}));
```

### Smart Allocation

```solidity
allocator.allocateFunds(token, amount, 0);  // 0 = auto-select
```

---

## 🔐 Security

### Pause Contract

```solidity
vault.pause();
```

### Unpause Contract

```solidity
vault.unpause();
```

### Emergency Withdraw

```solidity
l1Depositor.emergencyWithdraw(token, recipient, amount);
```

---

## 💡 Gas Management

### Fund Vault with Gas

```solidity
payable(vault).transfer(0.1 ether);
```

### Check Gas Balance

```solidity
uint256 gas = address(vault).balance;
```

### Set Min Gas Balance

```solidity
vault.setMinGasBalance(0.05 ether);
```

---

## 📝 Common Addresses

### Ethereum Mainnet

- **USDT**: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- **Across HubPool**: `0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5`
- **Chain ID**: `1`

### Ink L2

- **USDT0**: (Check Ink docs)
- **Tydro Pool**: (Check Ink docs)
- **Across SpokePool**: (Check Across docs)
- **Velodrome Router**: (Check Velodrome docs)
- **Chain ID**: (Check Ink docs)

---

## 🎯 Typical Workflows

### Initial Setup

1. Deploy L2 vault
2. Fund vault with gas
3. Deploy L1 depositor
4. Configure token mappings
5. Set L1 recipient
6. Transfer ownership to Safe (optional)

### Deposit Flow

1. Approve tokens
2. Deposit to L2
3. Wait for bridge (~2-3 seconds)
4. Auto-deposit to strategies

### Harvest Flow

1. Wait for yield (24-48 hours)
2. Check yield available
3. Harvest and bridge
4. Wait for bridge (~2-3 seconds)
5. Withdraw yield on L1

---

## ⚠️ Common Errors

| Error | Solution |
|-------|----------|
| `TokenNotSupported` | Set token mapping |
| `InsufficientGas` | Fund vault with ETH |
| `SlippageTooHigh` | Adjust minAmount or maxSlippageBps |
| `L2VaultNotSet` | Set L2 vault address |
| `L1RecipientNotSet` | Set L1 recipient address |

---

## 📚 Documentation Links

- [Main README](./README.md)
- [Architecture](./architecture/README.md)
- [Contracts](./contracts/README.md)
- [User Guide](./user-guide/README.md)
- [Deployment](./deployment/README.md)
- [Factory](./factory/README.md)
- [Strategies](./strategies/README.md)
- [Bridge](./bridge/README.md)

---

## 🔗 External Links

- [Foundry Book](https://book.getfoundry.sh/)
- [Across Protocol](https://docs.across.to/)
- [Ink L2](https://inkonchain.com/docs)
- [Gnosis Safe](https://docs.safe.global/)

---

**Keep this guide handy for quick reference!**

