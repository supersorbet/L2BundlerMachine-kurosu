// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title DeployL2
 * @notice Deployment script for BundledYieldVaultV2_PRODUCTION on Ink L2
 */
contract DeployL2 is Script {
    // Ink L2 addresses (Chain ID: 57073)
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA; // Tydro IPool on Ink
    address constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c; // Tydro L2Encoder on Ink
    address constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4; // Across SpokePool on Ink
    address constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C; // Velodrome Universal Router on Ink
    address constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    
    function run() external returns (address deployed) {
        // Handle private key with or without 0x prefix
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            // Parse as hex without 0x prefix
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        // L1 recipient - use deployer address if not set (can update later)
        address l1Recipient;
        try vm.envAddress("L1_RECIPIENT") returns (address recipient) {
            l1Recipient = recipient;
        } catch {
            // Use deployer address as fallback (can update later via setL1Recipient)
            l1Recipient = vm.addr(deployerPrivateKey);
            console.log("L1_RECIPIENT not set, using deployer address:", l1Recipient);
            console.log("You can update this later by calling setL1Recipient() on the vault");
        }
        
        require(TYDRO_POOL != address(0), "Set TYDRO_POOL address");
        require(L2_ENCODER != address(0), "Set L2_ENCODER address");
        require(ACROSS_SPOKE_POOL != address(0), "Set ACROSS_SPOKE_POOL address");
        require(VELO_ROUTER != address(0), "Set VELO_ROUTER address");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy L2 Vault
        BundledYieldVaultV2_PRODUCTION vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            l1Recipient,
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
        );
        
        vm.stopBroadcast();
        
        console.log("BundledYieldVaultV2_PRODUCTION deployed at:", address(vault));
        console.log("Owner:", vault.owner());
        console.log("L1 Recipient:", vault.l1Recipient());
        console.log("Tydro Pool:", vault.TYDRO_POOL());
        console.log("Across SpokePool:", vault.ACROSS_SPOKE_POOL());
        console.log("Velodrome Router:", vault.VELO_ROUTER());
        
        // Fund with gas
        console.log("\nTo fund the vault with gas, run:");
        console.log("cast send", address(vault), "--value 0.1ether --rpc-url $INK_RPC --private-key $PRIVATE_KEY");
        
        // Note: After deployment, you need to:
        // 1. Fund the vault with ETH for gas: cast send <vault> --value 0.1ether
        // 2. Call setTokenMapping(USDT0_L2, USDT_L1) where USDT0_L2 is the L2 token address
        // 3. Call setL1Recipient(<L1_DEPOSITOR_ADDRESS>) if not set in constructor
        // 4. Verify the deployment on Ink Explorer
        
        return address(vault);
    }
}

