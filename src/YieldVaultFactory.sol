// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BundledYieldVaultV2_PRODUCTION} from "./BundledYieldVaultV2_PRODUCTION.sol";

/// @title YieldVaultFactory
/// @notice Factory for deploying yield vaults for users
/// @dev Enables easy deployment and tracking of user vaults
contract YieldVaultFactory {
    struct VaultConfig {
        address tydroPool;
        address l2Encoder;
        address acrossSpokePool;
        address veloRouter;
        address slipstreamNFT;
    }
    
    /// @dev Default configuration (set in constructor)
    VaultConfig public defaultConfig;
    
    /// @dev Track all deployed vaults
    address[] public deployedVaults;
    
    /// @dev Mapping from vault address to owner
    mapping(address => address) public vaultOwners;
    
    /// @dev Mapping from owner to their vaults
    mapping(address => address[]) public ownerVaults;
    
    /// @dev Default keeper fee in basis points (e.g., 10 = 0.1%)
    uint256 public defaultKeeperFeeBps = 10;
    
    event VaultDeployed(address indexed vault, address indexed owner, address indexed l1Recipient);
    event DefaultKeeperFeeUpdated(uint256 oldFee, uint256 newFee);
    
    error InvalidAddress();
    error InvalidKeeperFee();
    
    constructor(
        address _tydroPool,
        address _l2Encoder,
        address _acrossSpokePool,
        address _veloRouter,
        address _slipstreamNFT,
        uint256 _defaultKeeperFeeBps
    ) {
        if (_tydroPool == address(0) || _l2Encoder == address(0) || 
            _acrossSpokePool == address(0) || _veloRouter == address(0) || _slipstreamNFT == address(0)) {
            revert InvalidAddress();
        }
        
        defaultConfig = VaultConfig({
            tydroPool: _tydroPool,
            l2Encoder: _l2Encoder,
            acrossSpokePool: _acrossSpokePool,
            veloRouter: _veloRouter,
            slipstreamNFT: _slipstreamNFT
        });
        
        if (_defaultKeeperFeeBps > 100) revert InvalidKeeperFee(); // Max 1%
        defaultKeeperFeeBps = _defaultKeeperFeeBps;
    }
    
    /// @notice Deploy vault for user
    /// @param l1Recipient L1Depositor address (receives bridged yield)
    /// @return vault Address of deployed vault
    function deployVault(address l1Recipient) external returns (address vault) {
        if (l1Recipient == address(0)) revert InvalidAddress();
        
        // Deploy new vault instance
        BundledYieldVaultV2_PRODUCTION newVault = new BundledYieldVaultV2_PRODUCTION(
            defaultConfig.tydroPool,
            defaultConfig.l2Encoder,
            defaultConfig.acrossSpokePool,
            l1Recipient,
            defaultConfig.veloRouter,
            defaultConfig.slipstreamNFT
        );
        
        // Set default keeper fee (if vault supports it)
        // Note: This requires adding setKeeperFee to vault contract
        // try newVault.setKeeperFee(defaultKeeperFeeBps) {} catch {}
        
        // Transfer ownership to deployer (msg.sender)
        newVault.transferOwnership(msg.sender);
        
        // Track deployment
        address vaultAddress = address(newVault);
        deployedVaults.push(vaultAddress);
        vaultOwners[vaultAddress] = msg.sender;
        ownerVaults[msg.sender].push(vaultAddress);
        
        emit VaultDeployed(vaultAddress, msg.sender, l1Recipient);
        
        return vaultAddress;
    }
    
    /// @notice Get all deployed vaults
    /// @return Array of all vault addresses
    function getAllVaults() external view returns (address[] memory) {
        return deployedVaults;
    }
    
    /// @notice Get vault count
    /// @return Number of deployed vaults
    function getVaultCount() external view returns (uint256) {
        return deployedVaults.length;
    }
    
    /// @notice Get vaults for a specific owner
    /// @param owner Owner address
    /// @return Array of vault addresses owned by owner
    function getVaultsForOwner(address owner) external view returns (address[] memory) {
        return ownerVaults[owner];
    }
    
    /// @notice Update default keeper fee (factory owner only)
    /// @param newFee New keeper fee in basis points
    function setDefaultKeeperFee(uint256 newFee) external {
        // Note: Add access control (onlyOwner) if needed
        if (newFee > 100) revert InvalidKeeperFee(); // Max 1%
        uint256 oldFee = defaultKeeperFeeBps;
        defaultKeeperFeeBps = newFee;
        emit DefaultKeeperFeeUpdated(oldFee, newFee);
    }
}

