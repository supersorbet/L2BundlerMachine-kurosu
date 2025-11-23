// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PROD} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title DeployMainnet
 * @notice Complete mainnet deployment script with safety checks
 * @dev Run with: forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url $ETH_RPC --broadcast --verify
 */
contract DeployMainnet is Script {
    // Ethereum Mainnet addresses
    address constant HUB_POOL = 0xc186fA914353c44b2E33eBE05f21846F1048bEda; // Across HubPool on Ethereum
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    
    // Ink L2 addresses (Chain ID: 57073)
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA; // Tydro IPool on Ink
    address constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c; // Tydro L2Encoder on Ink
    address constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4; // Across SpokePool on Ink
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1; // USDT0 on Ink L2
    uint256 constant INK_CHAIN_ID = 57073; // Ink chain ID
    address constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    
    function run() external {
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
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Mainnet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("\nNOTE: This script deploys L2 vault only.");
        console.log("For L1 deployment, use: forge script script/DeployL1.s.sol --rpc-url $ETH_RPC --broadcast");
        console.log("For L2 deployment, use: forge script script/DeployL2.s.sol --rpc-url $INK_RPC --broadcast");
        console.log("\nOr use the step-by-step guide in DEPLOY_MAINNET.md");
        
        // Check if we're deploying L2 (Ink) or L1 (Ethereum)
        string memory rpcUrl = vm.envString("RPC_URL");
        bool isInk = vm.envUint("INK_CHAIN_ID") == 57073 && 
                     keccak256(bytes(rpcUrl)) == keccak256(bytes(vm.envString("INK_RPC")));
        
        if (isInk) {
            console.log("\n=== Deploying L2 Vault on Ink ===");
            address l2Vault = _deployL2Vault(deployerPrivateKey);
            _fundL2Vault(l2Vault, deployerPrivateKey);
        console.log("\n[OK] L2 Vault deployment complete!");
        console.log("Next: Deploy L1 Depositor using DeployL1.s.sol");
        } else {
            console.log("\n=== Deploying L1 Depositor on Ethereum ===");
            address l2Vault = vm.envAddress("L2_VAULT");
            require(l2Vault != address(0), "L2_VAULT must be set in .env");
            address l1Depositor = _deployL1Depositor(l2Vault, deployerPrivateKey);
            _configureL1(l1Depositor, deployerPrivateKey);
            console.log("\n[OK] L1 Depositor deployment complete!");
            console.log("Next: Configure L2 vault with L1 recipient");
        }
    }
    
    function _deployL2Vault(uint256 deployerPrivateKey) internal returns (address) {
        address l1Recipient = vm.envAddress("L1_RECIPIENT"); // Can be deployer or L1 depositor (set after L1 deploy)
        if (l1Recipient == address(0)) {
            l1Recipient = vm.addr(deployerPrivateKey); // Use deployer as fallback
        }
        
        console.log("Deploying L2 Vault on Ink...");
        console.log("L1 Recipient (temporary):", l1Recipient);
        console.log("Tydro Pool:", TYDRO_POOL);
        console.log("L2 Encoder:", L2_ENCODER);
        console.log("Across SpokePool:", ACROSS_SPOKE_POOL);
        
        vm.startBroadcast(deployerPrivateKey);
        
        BundledYieldVaultV2_PRODUCTION vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            l1Recipient,
            0x01D40099fCD87C018969B0e8D4aB1633Fb34763C, // Velodrome router
            SLIPSTREAM_POSITION_NFT
        );
        
        vm.stopBroadcast();
        
        console.log("[OK] L2 Vault deployed at:", address(vault));
        console.log("Owner:", vault.owner());
        
        return address(vault);
    }
    
    function _fundL2Vault(address vault, uint256 deployerPrivateKey) internal {
        console.log("Funding L2 vault with 0.01 ETH for gas...");
        
        vm.startBroadcast(deployerPrivateKey);
        (bool success,) = vault.call{value: 0.01 ether}("");
        require(success, "Failed to fund vault");
        vm.stopBroadcast();
        
        console.log("[OK] L2 Vault funded with 0.01 ETH");
    }
    
    function _deployL1Depositor(address l2Vault, uint256 deployerPrivateKey) internal returns (address) {
        console.log("Deploying L1 Depositor on Ethereum...");
        console.log("L2 Vault:", l2Vault);
        console.log("Hub Pool:", HUB_POOL);
        console.log("Destination Chain ID:", INK_CHAIN_ID);
        
        vm.startBroadcast(deployerPrivateKey);
        
        L1DepositorV2_PROD depositor = new L1DepositorV2_PROD(
            HUB_POOL,
            l2Vault,
            INK_CHAIN_ID
        );
        
        vm.stopBroadcast();
        
        console.log("[OK] L1 Depositor deployed at:", address(depositor));
        console.log("Owner:", depositor.owner());
        
        return address(depositor);
    }
    
    function _configureL1(address l1Depositor, uint256 deployerPrivateKey) internal {
        console.log("Configuring L1 token mapping...");
        vm.startBroadcast(deployerPrivateKey);
        L1DepositorV2_PROD depositor = L1DepositorV2_PROD(l1Depositor);
        depositor.setTokenMapping(USDT_L1, USDT0_L2);
        console.log("[OK] L1: Set token mapping USDT -> USDT0");
        vm.stopBroadcast();
    }
}

