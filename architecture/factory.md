# Factory Pattern

## Overview

The Yield Vault Factory enables users to deploy their own private vault instances, providing isolation, ownership, and customization.

***

## Factory Contract

### YieldVaultFactory

The factory contract deploys new vault instances:

```solidity
contract YieldVaultFactory {
    function deployVault(address l1Recipient) external returns (address vault) {
        // Deploy new vault instance
        // Transfer ownership to deployer
        // Track deployment
    }
}
```

### Deployment Process

1. **User Calls Factory**: User calls `deployVault()` with their L1 recipient address
2. **Vault Creation**: Factory deploys new BundledYieldVaultV2 instance
3. **Ownership Transfer**: Ownership is transferred to deployer
4. **Deployment Tracking**: Factory records the deployment
5. **Return Address**: Factory returns the new vault address

***

## Vault Deployment

### Deployment Parameters

* **l1Recipient**: Address of the L1Depositor contract (or user's preferred recipient)
* **Deployer**: Automatically set as the `msg.sender` (becomes owner)

### Deployment Code

```solidity
function deployVault(address l1Recipient) external returns (address vault) {
    // Deploy new vault instance
    BundledYieldVaultV2 newVault = new BundledYieldVaultV2(l1Recipient);
    
    // Transfer ownership to deployer
    newVault.transferOwnership(msg.sender);
    
    // Track deployment
    deployments[msg.sender] = address(newVault);
    
    emit VaultDeployed(msg.sender, address(newVault));
    
    return address(newVault);
}
```

***

## Benefits

### 1. Isolation

* ✅ Each user gets their own isolated vault
* ✅ No shared state between users
* ✅ Independent yield tracking
* ✅ Separate risk profiles

### 2. Ownership

* ✅ Full ownership and control
* ✅ Owner-only operations
* ✅ Customizable per vault
* ✅ Independent configuration

### 3. Security

* ✅ No shared risks
* ✅ Isolated failure domains
* ✅ Independent access control
* ✅ Separate upgrade paths

### 4. Customization

* ✅ Per-vault token mappings
* ✅ Custom strategy allocations
* ✅ Independent yield settings
* ✅ Flexible configuration

***

## Use Cases

### Individual Users

* Deploy personal vault
* Full control over deposits and withdrawals
* Private yield tracking
* Custom strategy preferences

### Institutions

* Deploy institutional vault
* Separate from retail users
* Custom compliance settings
* Independent audit trail

### Protocols

* Integrate vault into protocol
* Isolated yield management
* Custom integration logic
* Protocol-specific configurations

***

## Factory Features

### Deployment Tracking

* Records all deployments
* Maps deployers to vaults
* Enables discovery and verification
* Supports analytics

### Event Emissions

```solidity
event VaultDeployed(address indexed deployer, address indexed vault);
```

### Query Functions

* `getVault(address deployer)`: Get vault address for deployer
* `isDeployed(address vault)`: Verify vault was deployed by factory
* `totalDeployments()`: Count total deployments

***

## Integration

### With L1Depositor

1. Deploy vault via factory
2. Configure L1Depositor with vault address
3. Set token mappings
4. Begin depositing

### With Strategies

1. Deploy vault
2. Configure strategy addresses
3. Set allocation preferences
4. Start yield farming

***

## Related Documentation

* [Contract Responsibilities](contracts.md) - Factory contract details
* [Deployment Guide](broken-reference) - How to deploy vaults
* [User Guide](../user-guide/) - Using deployed vaults
