// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title SetupL2
 * @notice Configure L2 vault after L1 deployment
 * @dev Run with: forge script script/SetupL2.s.sol:SetupL2 --rpc-url $INK_RPC --broadcast
 */
contract SetupL2 is Script {
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1; // USDT0 on Ink L2
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    
    function run() external {
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            // Parse as hex without 0x prefix
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        address l2Vault = vm.envAddress("L2_VAULT");
        address l1Depositor = vm.envAddress("L1_DEPOSITOR");
        
        require(l2Vault != address(0), "L2_VAULT must be set in .env");
        require(l1Depositor != address(0), "L1_DEPOSITOR must be set in .env");
        
        console.log("^__^ Configuring L2 Vault ^__^");
        console.log("L2 Vault:", l2Vault);
        console.log("L1 Depositor:", l1Depositor);
        
        vm.startBroadcast(deployerPrivateKey);
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(payable(l2Vault));
        
        // Set token mapping
        vault.mapToken(USDT0_L2, USDT_L1);
        console.log("[OK] Set token mapping USDT0 -> USDT");
        
        // Set L1 recipient
        vault.setL1Recipient(l1Depositor);
        console.log("[OK] Set L1 recipient to L1 Depositor");
        
        vm.stopBroadcast();
        
        console.log("\n[OK] L2 Vault configuration complete!");
    }
}

