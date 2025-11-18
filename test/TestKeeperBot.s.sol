// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";

/// @title TestKeeperBot
/// @notice Script to seed keeper address and test keeper bot functionality on mainnet forks
/// @dev Run with: forge script test/TestKeeperBot.s.sol --fork-url $INK_RPC -vvvv
contract TestKeeperBot is Script {
    // Ink L2 addresses
    address public constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    address public constant USDT0_L2_WHALE = 0x2D27Bf7AD3303bDCF341C5890296Ad8B49D68829;
    
    // Default keeper address (can be overridden via env)
    address public constant DEFAULT_KEEPER = 0x601BC5928f447d8f38Ba644579AD6a116A53e0D6;
    
    function run() external {
        // Get keeper address from env or use default
        address keeper = vm.envOr("KEEPER_ADDRESS", DEFAULT_KEEPER);
        uint256 ethAmount = vm.envOr("KEEPER_ETH_AMOUNT", uint256(1 ether));
        uint256 tokenAmount = vm.envOr("KEEPER_TOKEN_AMOUNT", uint256(0));
        
        console.log("=== Seeding Keeper Bot ===");
        console.log("Keeper Address:", keeper);
        console.log("ETH Amount:", ethAmount / 1e18, "ETH");
        console.log("");
        
        // Seed ETH
        vm.deal(keeper, ethAmount);
        uint256 balance = address(keeper).balance;
        console.log("Keeper ETH Balance:", balance / 1e18, "ETH");
        
        // Seed tokens if requested
        if (tokenAmount > 0) {
            console.log("");
            console.log("Seeding tokens from whale...");
            console.log("Token:", USDT0_L2);
            console.log("Whale:", USDT0_L2_WHALE);
            console.log("Amount:", tokenAmount / 1e6, "USDT");
            
            vm.startPrank(USDT0_L2_WHALE);
            (bool success, bytes memory data) = USDT0_L2.call(
                abi.encodeWithSignature("transfer(address,uint256)", keeper, tokenAmount)
            );
            vm.stopPrank();
            
            if (success) {
                // Check balance
                (bool balanceSuccess, bytes memory balanceData) = USDT0_L2.staticcall(
                    abi.encodeWithSignature("balanceOf(address)", keeper)
                );
                if (balanceSuccess && balanceData.length >= 32) {
                    uint256 keeperBalance = abi.decode(balanceData, (uint256));
                    console.log("Keeper Token Balance:", keeperBalance / 1e6, "USDT");
                }
                console.log("Tokens seeded successfully");
            } else {
                console.log("Token seeding failed (whale may not have balance on fork)");
            }
        }
        
        // Get vault address
        address vault = vm.envAddress("VAULT_ADDRESS");
        console.log("");
        console.log("=== Vault Information ===");
        console.log("Vault Address:", vault);
        
        // Check vault state
        (bool pausedSuccess, bytes memory pausedData) = vault.staticcall(
            abi.encodeWithSignature("paused()")
        );
        if (pausedSuccess && pausedData.length >= 32) {
            bool isPaused = abi.decode(pausedData, (bool));
            console.log("Vault Paused:", isPaused);
        }
        
        // Check if token is registered
        (bool mappingSuccess, bytes memory mappingData) = vault.staticcall(
            abi.encodeWithSignature("tokenMapping(address)", USDT0_L2)
        );
        if (mappingSuccess && mappingData.length >= 32) {
            address l1Token = abi.decode(mappingData, (address));
            if (l1Token != address(0)) {
                console.log("Token Registered: Yes (L1:", l1Token, ")");
            } else {
                console.log("Token Registered: No");
            }
        }
        
        console.log("");
        console.log("=== Keeper Ready ===");
        console.log("Keeper Address:", keeper);
        console.log("ETH Balance:", balance / 1e18, "ETH");
        console.log("");
        console.log("Run keeper bot with:");
        console.log("  export KEEPER_ADDRESS=", keeper);
        console.log("  export VAULT_ADDRESS=", vault);
        console.log("  node keeper_bot.js --network ink --rpc $INK_RPC --vault", vault, "--tokens", USDT0_L2);
    }
}

