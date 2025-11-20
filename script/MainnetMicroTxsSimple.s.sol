// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainnetMicroTxsSimple is Script {
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    uint256 constant MICRO_DEPOSIT_TYDRO = 1 * 1e6; // $1 USDT
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address vaultAddress = vm.envAddress("L2_VAULT_ADDRESS");
        require(vaultAddress != address(0), "L2_VAULT_ADDRESS not set");
        
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(payable(vaultAddress));
        require(vault.owner() == deployer, "Deployer must be vault owner");
        
        console.log("=== MAINNET MICRO TX: TYDRO DEPOSIT ONLY ===");
        console.log("Deployer:", deployer);
        console.log("Vault:", vaultAddress);
        console.log("");
        
        vm.startBroadcast();
        
        // Check balance
        uint256 usdtBalance = IERC20(USDT0_L2).balanceOf(deployer);
        console.log("Deployer USDT0 balance:", usdtBalance / 1e6);
        
        if (usdtBalance >= MICRO_DEPOSIT_TYDRO) {
            // Approve and deposit
            IERC20(USDT0_L2).approve(vaultAddress, MICRO_DEPOSIT_TYDRO);
            vault.deposit(USDT0_L2, MICRO_DEPOSIT_TYDRO);
            console.log("Deposited", MICRO_DEPOSIT_TYDRO / 1e6, "USDT0 to Tydro");
            
            // Check status
            (uint256 deposited, , , ) = vault.getStatus(USDT0_L2);
            console.log("Total deposited:", deposited / 1e6);
        } else {
            console.log("SKIP: Insufficient USDT0 balance");
        }
        
        console.log("=== TX COMPLETE ===");
        vm.stopBroadcast();
    }
}
