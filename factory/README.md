# Factory & Private Vault Deployment

## Overview

The `YieldVaultFactory` enables users to deploy their own **private, isolated vault instances**. Each vault is fully owned by the deployer and operates independently, providing complete control and security.

---

## 🏭 Factory Pattern Benefits

### Why Use the Factory?

- ✅ **Isolation**: Each vault is completely separate
- ✅ **Ownership**: Full control over your vault
- ✅ **Privacy**: No shared state with other users
- ✅ **Customization**: Configure per-vault settings
- ✅ **Security**: Isolated risk - one vault's issues don't affect others

### Use Cases

1. **Private Treasury Management**: Deploy your own vault for treasury operations
2. **Institutional Funds**: Separate vaults for different funds/strategies
3. **DAO Operations**: Deploy vaults for specific DAO initiatives
4. **Testing**: Deploy test vaults without affecting production

---

## 📋 Factory Contract

### Contract Address

The factory is deployed on **Ink L2** and uses a standardized configuration.

### Configuration

```solidity
struct VaultConfig {
    address tydroPool;        // Tydro lending pool
    address l2Encoder;        // L2 encoder for compressed calldata
    address acrossSpokePool;  // Across bridge SpokePool
    address veloRouter;       // Velodrome router
}
```

All deployed vaults use the same infrastructure addresses, ensuring consistency and security.

---

## 🚀 Deploying Your Vault

### Step 1: Prepare L1 Depositor

First, ensure you have an L1Depositor contract deployed on Ethereum Mainnet. This will receive bridged yield from your vault.

```solidity
// Deploy L1Depositor (if not already deployed)
L1DepositorV2_PRODUCTION l1Depositor = new L1DepositorV2_PRODUCTION(
    HUB_POOL,
    address(0),  // L2 vault (set after deployment)
    INK_CHAIN_ID
);
```

### Step 2: Deploy Vault via Factory

```solidity
// Deploy your private vault
address myVault = factory.deployVault(address(l1Depositor));
```

**What happens**:
1. Factory creates new `BundledYieldVaultV2_PRODUCTION` instance
2. Ownership is transferred to you (msg.sender)
3. Vault is configured with factory's default settings
4. Vault address is tracked and indexed

### Step 3: Configure Your Vault

After deployment, configure your vault:

```solidity
// Set token mappings
myVault.setTokenMapping(usdt0L2, usdtL1);

// Set L1 recipient (if different from constructor)
myVault.setL1Recipient(address(l1Depositor));

// Configure settings
myVault.setDefaultCompoundPercent(50);  // 50% compound, 50% bridge
myVault.setMinGasBalance(0.01 ether);
```

### Step 4: Fund Your Vault

Send ETH to your vault for gas:

```solidity
// Fund vault with ETH for gas
(bool success,) = myVault.call{value: 0.1 ether}("");
require(success, "Funding failed");
```

---

## 🔐 Ownership & Access Control

### Ownership Model

Each vault uses **Ownable** from Solady:

```solidity
contract BundledYieldVaultV2_PRODUCTION is Ownable {
    // All critical functions are owner-only
    modifier onlyOwner() {
        if (msg.sender != owner()) revert Unauthorized();
        _;
    }
}
```

### Transferring Ownership

You can transfer vault ownership (e.g., to a Gnosis Safe):

```solidity
// Transfer to Gnosis Safe
myVault.transferOwnership(gnosisSafeAddress);

// New owner must accept
// (if using Safe, create a transaction to accept ownership)
```

### Gnosis Safe Integration

**Recommended Setup**:

1. Deploy vault with your EOA
2. Transfer ownership to Gnosis Safe multisig
3. Configure Safe with required signers
4. All operations now require multisig approval

**Example Safe Transaction**:
```solidity
// In Gnosis Safe interface
// Transaction: depositAvailable(usdt0, true)
// Requires: 2 of 3 signatures
```

---

## 📊 Vault Management

### Querying Your Vaults

```solidity
// Get all your vaults
address[] memory myVaults = factory.getVaultsForOwner(msg.sender);

// Get vault count
uint256 count = factory.getVaultCount();

// Get all deployed vaults
address[] memory allVaults = factory.getAllVaults();
```

### Vault Status

Check your vault's status:

```solidity
// Get token status
(uint256 deposited, uint256 balance, uint256 yield, uint256 gas) = 
    myVault.getStatus(usdt0);

// Get yield available
uint256 availableYield = myVault.getYieldAvailable(usdt0);
```

---

## 🎯 Complete Deployment Example

### Full Workflow

```solidity
// 1. Deploy L1 Depositor (Ethereum)
L1DepositorV2_PRODUCTION l1Depositor = new L1DepositorV2_PRODUCTION(
    0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5, // HubPool
    address(0),  // L2 vault (set later)
    11155111     // Ink chain ID
);

// 2. Deploy L2 Vault via Factory (Ink L2)
YieldVaultFactory factory = YieldVaultFactory(factoryAddress);
address myVault = factory.deployVault(address(l1Depositor));

// 3. Update L1 Depositor with L2 Vault
l1Depositor.setL2Vault(myVault);

// 4. Configure token mappings
l1Depositor.setTokenMapping(usdtL1, usdt0L2);
BundledYieldVaultV2_PRODUCTION(myVault).setTokenMapping(usdt0L2, usdtL1);

// 5. Fund vault with gas
payable(myVault).transfer(0.1 ether);

// 6. Transfer ownership to Gnosis Safe (optional)
BundledYieldVaultV2_PRODUCTION(myVault).transferOwnership(safeAddress);
```

---

## 🔧 Factory Configuration

### Default Settings

The factory uses standardized settings:

- **Tydro Pool**: Production Tydro pool address
- **L2 Encoder**: Standard encoder for compressed calldata
- **Across SpokePool**: Production SpokePool address
- **Velodrome Router**: Production router address

### Updating Factory Settings

Factory owner can update default keeper fee:

```solidity
// Update default keeper fee (basis points)
factory.setDefaultKeeperFee(10);  // 0.1%
```

---

## 🛡️ Security Considerations

### Isolated Vaults

Each vault is completely isolated:
- ✅ Separate storage
- ✅ Separate ownership
- ✅ No shared state
- ✅ Independent risk

### Access Control

- **Owner-only operations**: All critical functions require ownership
- **No shared permissions**: Each vault owner has full control
- **Transferable ownership**: Can transfer to multisig for added security

### Best Practices

1. **Use Multisig**: Transfer ownership to Gnosis Safe
2. **Monitor Gas**: Keep vault funded with ETH
3. **Regular Harvests**: Set up keeper for automated harvesting
4. **Token Mappings**: Verify mappings before deposits

---

## 📈 Vault Lifecycle

### 1. Deployment
- Factory creates new vault instance
- Ownership transferred to deployer
- Vault configured with defaults

### 2. Configuration
- Set token mappings
- Configure L1 recipient
- Set yield parameters

### 3. Operation
- Deposit tokens
- Auto-deposit to strategies
- Harvest yield
- Bridge yield to L1

### 4. Management
- Monitor vault status
- Adjust settings as needed
- Transfer ownership if required

---

## 🔗 Related Documentation

- [Core Contracts](./../contracts/README.md)
- [User Guide](./../user-guide/README.md)
- [Deployment Guide](./../deployment/README.md)
- [Architecture Overview](./../architecture/README.md)

