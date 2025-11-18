// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";

/**
 * @title SetupL1
 * @notice Configure L1 depositor with token mappings
 * @dev Run with: forge script script/SetupL1.s.sol:SetupL1 --rpc-url $ETH_RPC --broadcast
 */
contract SetupL1 is Script {
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1; // USDT0 on Ink L2
    
    function run() external {
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        
        address l1Depositor = vm.envAddress("L1_DEPOSITOR");
        require(l1Depositor != address(0), "L1_DEPOSITOR must be set in .env");
        
        console.log("^__^ Configuring L1 Depositor ^__^");
        console.log("L1 Depositor:", l1Depositor);
        console.log("USDT L1:", USDT_L1);
        console.log("USDT0 L2:", USDT0_L2);
        
        vm.startBroadcast(deployerPrivateKey);
        L1DepositorV2_PRODUCTION depositor = L1DepositorV2_PRODUCTION(payable(l1Depositor));
        
        // Set token mapping: USDT (L1) -> USDT0 (L2)
        depositor.setTokenMapping(USDT_L1, USDT0_L2);
        console.log("[OK] Set token mapping USDT -> USDT0");
        
        vm.stopBroadcast();
        
        console.log("\n[OK] L1 Depositor configuration complete!");
    }
}

