// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";

/**
 * @title DeployL1
 * @notice Deployment script for L1DepositorV2_PRODUCTION on Ethereum Mainnet
 */
contract DeployL1 is Script {
    // Ethereum Mainnet addresses
    address constant HUB_POOL = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5; // Across HubPool
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    
    function run() external returns (address deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address l2Vault = vm.envAddress("L2_VAULT"); // L2 vault address from deployment
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy L1Depositor
        // Note: Update destinationChainId with actual Ink L2 chain ID
        uint256 destinationChainId = vm.envUint("INK_CHAIN_ID"); // Set in .env
        L1DepositorV2_PRODUCTION depositor = new L1DepositorV2_PRODUCTION(
            HUB_POOL,
            l2Vault,
            destinationChainId
        );
        
        vm.stopBroadcast();
        
        console.log("L1DepositorV2_PRODUCTION deployed at:", address(depositor));
        console.log("Owner:", depositor.owner());
        console.log("L2 Vault:", depositor.l2Vault());
        
        // Note: After deployment, you need to:
        // 1. Call setTokenMapping(USDT_L1, USDT0_L2) where USDT0_L2 is the L2 token address
        // 2. Verify the deployment on Etherscan
        
        return address(depositor);
    }
}

