// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PROD} from "../src/L1DepositorV2_PRODUCTION.sol";

/**
 * @title DeployL1
 * @notice Deployment script for L1DepositorV2_PRODUCTION on Ethereum Mainnet
 */
contract DeployL1 is Script {
    // Ethereum Mainnet addresses
    address constant HUB_POOL = 0xc186fA914353c44b2E33eBE05f21846F1048bEda; // Across HubPool on Ethereum
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    
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
        address l2Vault = vm.envAddress("L2_VAULT"); // L2 vault address from deployment
        require(l2Vault != address(0), "L2_VAULT must be set in .env. Deploy L2 vault first using: forge script script/DeployL2.s.sol:DeployL2 --rpc-url $INK_RPC --broadcast");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy L1Depositor
        // Note: Update destinationChainId with actual Ink L2 chain ID
        uint256 destinationChainId = 57073; // Ink chain ID
        // Try to read from env, but use default if not set
        try vm.envUint("INK_CHAIN_ID") returns (uint256 chainId) {
            destinationChainId = chainId;
        } catch {}
        L1DepositorV2_PROD depositor = new L1DepositorV2_PROD(
            HUB_POOL,
            l2Vault,
            destinationChainId
        );
        
        vm.stopBroadcast();
        
        console.log("L1DepositorV2_PROD deployed at:", address(depositor));
        console.log("Owner:", depositor.owner());
        console.log("L2 Vault:", depositor.l2Vault());
        
        // Note: After deployment, you need to:
        // 1. Call setTokenMapping(USDT_L1, USDT0_L2) where USDT0_L2 is the L2 token address
        // 2. Verify the deployment on Etherscan
        
        return address(depositor);
    }
}

