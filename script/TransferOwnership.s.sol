// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title TransferOwnership
 * @notice Transfer vault ownership to current deployer
 * @dev Run with the PRIVATE_KEY that owns the vault (0x00000009eEE278329552382a472A7d06c773D7B3)
 */
contract TransferOwnership is Script {
    function run() external {
        // Handle private key with or without 0x prefix
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        
        address currentOwner = vm.addr(deployerPrivateKey);
        address l2Vault = vm.envAddress("L2_VAULT");
        address newOwner = vm.envAddress("NEW_OWNER"); // Set this to 0xca1B9E4D92cFE302818bcFbbf2BAfA9a34e4698A
        
        require(newOwner != address(0), "NEW_OWNER must be set in .env");
        
        console.log("=== Transfer Ownership ===");
        console.log("Current owner (from PRIVATE_KEY):", currentOwner);
        console.log("New owner:", newOwner);
        console.log("L2 Vault:", l2Vault);
        
        vm.startBroadcast(deployerPrivateKey);
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(payable(l2Vault));
        vault.transferOwnership(newOwner);
        vm.stopBroadcast();
        
        console.log("[OK] Ownership transferred!");
    }
}

