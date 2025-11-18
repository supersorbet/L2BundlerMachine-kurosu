// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title TestMainnet
 * @notice Test script for mainnet with smol amounts
 * @dev Run with: forge script script/TestMainnet.s.sol:TestMainnet --rpc-url $ETH_RPC --broadcast
 */
contract TestMainnet1 is Script {
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT on Ethereum
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1; // USDT0 on Ink L2
    
    // Small test amounts (in USDT units, 6 decimals)
    uint256 constant TEST_DEPOSIT_AMOUNT = 100_000; // $0.10 USDT
    uint256 constant MIN_OUTPUT_AMOUNT = 95_000; // 5% slippage tolerance
    
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
        
        address l1Depositor = vm.envAddress("L1_DEPOSITOR");
        address l2Vault = vm.envAddress("L2_VAULT");
        
        require(l1Depositor != address(0), "L1_DEPOSITOR not set");
        require(l2Vault != address(0), "L2_VAULT not set");
        
        console.log("++++ Mainnet Test with smol Amounts ===");
        console.log("Deployer:", deployer);
        console.log("L1 Depositor:", l1Depositor);
        console.log("L2 Vault:", l2Vault);
        console.log("Test Amount:", TEST_DEPOSIT_AMOUNT, "($0.10 USDT)");
        
        // Step 1: Check balances
        console.log("\n=== Step 1: Check Balances ===");
        uint256 ethBalance = deployer.balance;
        uint256 usdtBalance = _getUSDTBalance(deployer);
        console.log("Deployer ETH:", ethBalance);
        console.log("Deployer USDT:", usdtBalance);
        
        require(ethBalance > 0.001 ether, "Insufficient ETH for gas");
        require(usdtBalance >= TEST_DEPOSIT_AMOUNT, "Insufficient USDT for test");
        
        // Step 2: Approve USDT
        console.log("\n=== Step 2: Approve USDT ===");
        _approveUSDT(l1Depositor, deployerPrivateKey);
        
        // Step 3: Deposit to L2
        console.log("\n=== Step 3: Deposit to L2 via Across ===");
        _depositToL2(l1Depositor, deployerPrivateKey);
        
        console.log("\n=== Test Complete ===");
        console.log("Wait 2-3 minutes for Across bridge to complete");
        console.log("Then check L2 vault balance and deposit to Tydro");
    }
    
    function _getUSDTBalance(address account) internal view returns (uint256) {
        (bool success, bytes memory data) = USDT_L1.staticcall(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }
    
    function _approveUSDT(address spender, uint256 deployerPrivateKey) internal {
        console.log("Approving USDT...");
        vm.startBroadcast(deployerPrivateKey);
        (bool success,) = USDT_L1.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, TEST_DEPOSIT_AMOUNT)
        );
        vm.stopBroadcast();
        require(success, "USDT approval failed");
        console.log("[OK] USDT approved");
    }
    
    function _depositToL2(address l1Depositor, uint256 deployerPrivateKey) internal {
        console.log("Depositing", TEST_DEPOSIT_AMOUNT, "USDT to L2...");
        vm.startBroadcast(deployerPrivateKey);
        L1DepositorV2_PRODUCTION depositor = L1DepositorV2_PRODUCTION(l1Depositor);
        depositor.depositToL2(USDT_L1, TEST_DEPOSIT_AMOUNT, MIN_OUTPUT_AMOUNT);
        vm.stopBroadcast();
        console.log("[OK] Deposit transaction sent");
        console.log("Transaction will bridge via Across to Ink L2");
    }
}

