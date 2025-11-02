// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title Setup
 * @notice Configuration script to set up token mappings and connections after deployment
 */
contract Setup is Script {
    // Ethereum Mainnet
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant HUB_POOL_L1 = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    
    function run() external {
        // Load addresses from environment
        address l1Depositor = vm.envAddress("L1_DEPOSITOR");
        address l2Vault = vm.envAddress("L2_VAULT");
        address usdt0L2 = vm.envAddress("USDT0_L2"); // USDT0 address on Ink
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("Setting up contracts...");
        console.log("L1 Depositor:", l1Depositor);
        console.log("L2 Vault:", l2Vault);
        console.log("USDT L1:", USDT_L1);
        console.log("USDT0 L2:", usdt0L2);
        
        // Setup L1
        console.log("\n=== Setting up L1 ===");
        vm.startBroadcast(deployerPrivateKey);
        
        L1DepositorV2_PRODUCTION depositor = L1DepositorV2_PRODUCTION(l1Depositor);
        
        // Set token mapping: USDT (L1) -> USDT0 (L2)
        depositor.setTokenMapping(USDT_L1, usdt0L2);
        console.log("[OK] Set L1 token mapping: USDT -> USDT0");
        
        // Set L2 vault if not already set
        if (depositor.l2Vault() != l2Vault) {
            depositor.setL2Vault(l2Vault);
            console.log("[OK] Set L2 vault address");
        }
        
        vm.stopBroadcast();
        
        // Setup L2 (note: this requires Ink RPC)
        console.log("\n=== Setting up L2 ===");
        console.log("Note: Run L2 setup on Ink network with --rpc-url https://rpc-gel.inkonchain.com");
        console.log("\nTo set L2 mappings manually:");
        console.log("1. setTokenMapping(USDT0_L2, USDT_L1)");
        console.log("2. setL1Recipient(L1_DEPOSITOR)");
    }
}

