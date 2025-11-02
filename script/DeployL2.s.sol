// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title DeployL2
 * @notice Deployment script for BundledYieldVaultV2_PRODUCTION on Ink L2
 */
contract DeployL2 is Script {
    // You need to set these addresses based on Ink documentation
    address constant TYDRO_POOL = address(0); // TODO: Set Tydro pool address from Ink docs
    address constant ACROSS_SPOKE_POOL = address(0); // TODO: Set Across SpokePool address on Ink
    
    function run() external returns (address deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address l1Recipient = vm.envAddress("L1_RECIPIENT"); // L1 depositor address
        
        require(TYDRO_POOL != address(0), "Set TYDRO_POOL address");
        require(ACROSS_SPOKE_POOL != address(0), "Set ACROSS_SPOKE_POOL address");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy L2 Vault
        BundledYieldVaultV2_PRODUCTION vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            ACROSS_SPOKE_POOL,
            l1Recipient
        );
        
        vm.stopBroadcast();
        
        console.log("BundledYieldVaultV2_PRODUCTION deployed at:", address(vault));
        console.log("Owner:", vault.owner());
        console.log("L1 Recipient:", vault.l1Recipient());
        console.log("Tydro Pool:", vault.TYDRO_POOL());
        console.log("Across SpokePool:", vault.ACROSS_SPOKE_POOL());
        
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

