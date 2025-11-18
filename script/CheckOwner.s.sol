// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title CheckOwner
 * @notice Check vault ownership and deployer address
 */
contract CheckOwner is Script {
    function run() external view {
        // Handle private key with or without 0x prefix
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        address l2Vault = vm.envAddress("L2_VAULT");
        
        console.log("=== Ownership Check ===");
        console.log("Deployer address (from PRIVATE_KEY):", deployer);
        console.log("L2 Vault address:", l2Vault);
        
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(payable(l2Vault));
        address owner = vault.owner();
        
        console.log("Vault owner:", owner);
        console.log("");
        
        if (deployer == owner) {
            console.log("[OK] Deployer is the owner - you can configure the vault!");
        } else {
            console.log("[WARNING] Deployer is NOT the owner!");
            console.log("You need to use the private key that deployed the vault");
            console.log("Or the current owner needs to transfer ownership to:", deployer);
        }
    }
}

