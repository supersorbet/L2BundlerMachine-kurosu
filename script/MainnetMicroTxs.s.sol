// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MainnetMicroTxs
 * @notice Execute real micro transactions on Ink L2 mainnet for documentation
 * @dev Run with: forge script script/MainnetMicroTxs.s.sol:MainnetMicroTxs --rpc-url $INK_RPC --broadcast --verify
 * @dev Set PRIVATE_KEY, L2_VAULT_ADDRESS, and optionally TREASURY_ADDRESS in .env
 */
contract MainnetMicroTxs is Script {
    // Ink L2 addresses
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    address constant USDC_L2 = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address constant WETH_L2 = 0x4200000000000000000000000000000000000006;
    
    // Micro amounts (very small for documentation)
    uint256 constant MICRO_DEPOSIT_TYDRO = 1 * 1e6; // $1 USDT
    uint256 constant MICRO_DEPOSIT_VELO = 5 * 1e6; // $5 USDT
    uint256 constant MICRO_DEPOSIT_SLIPSTREAM = 10 * 1e6; // $10 USDT
    
    function run() external {
        // Get private key from .env (vm.startBroadcast will read PRIVATE_KEY automatically)
        // But we need it to get the deployer address for checks
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get vault address
        address vaultAddress = vm.envAddress("L2_VAULT_ADDRESS");
        require(vaultAddress != address(0), "L2_VAULT_ADDRESS not set");
        
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(payable(vaultAddress));
        
        // Verify deployer is owner
        require(vault.owner() == deployer, "Deployer must be vault owner");
        
        console.log("420 MAINNET MICRO TRANSACTIONS FOR DOCUMENTATION 420");
        console.log("Deployer:", deployer);
        console.log("Vault:", vaultAddress);
        console.log("Velo Helper:", vault.VELO_HELPER());
        console.log("Slipstream Helper:", vault.SLIPSTREAM_HELPER());
        console.log("Network: Ink L2 Mainnet");
        console.log("");
        
        // vm.startBroadcast reads PRIVATE_KEY from .env automatically
        vm.startBroadcast();
        
        // 6969696696969696969 TX 1: TYDRO DEPOSIT 6969696696969696969
        console.log("420 TX 1: TYDRO DEPOSIT 420");
        uint256 usdtBalance = IERC20(USDT0_L2).balanceOf(deployer);
        console.log("Deployer USDT0 balance:", usdtBalance / 1e6);
        
        if (usdtBalance >= MICRO_DEPOSIT_TYDRO) {
            IERC20(USDT0_L2).approve(vaultAddress, MICRO_DEPOSIT_TYDRO);
            vault.deposit(USDT0_L2, MICRO_DEPOSIT_TYDRO);
            console.log("Deposited", MICRO_DEPOSIT_TYDRO / 1e6, "USDT0 to Tydro");
            
            // Check status
            (uint256 deposited, , , ) = vault.getStatus(USDT0_L2);
            console.log("Total deposited:", deposited / 1e6);
        } else {
            console.log("SKIP: Insufficient USDT0 balance");
        }
        
        console.log("");
        
        // 6969696696969696969 TX 2: SLIPSTREAM ZAP (via SlipstreamHelper) 6969696696969696969
        console.log("420 TX 2: SLIPSTREAM ZAP (via SlipstreamHelper) 420");
        usdtBalance = IERC20(USDT0_L2).balanceOf(deployer);
        console.log("Deployer USDT0 balance:", usdtBalance / 1e6);
        
        if (usdtBalance >= MICRO_DEPOSIT_VELO) {
            // Transfer to vault first (vault needs tokens to zap)
            IERC20(USDT0_L2).transfer(vaultAddress, MICRO_DEPOSIT_VELO);
            console.log("Transferred", MICRO_DEPOSIT_VELO / 1e6, "USDT0 to vault");
            
            // Zap into Slipstream position (USDT0/USDC pair)
            // This calls SlipstreamHelper.zapIntoPosition internally
            // Uses Velodrome router for swap, then creates Slipstream NFT position
            uint256 tokenId = vault.zapIntoSlipstreamPosition(
                USDT0_L2,
                USDC_L2,
                MICRO_DEPOSIT_VELO,
                100, // 0.01% fee tier
                -887220, // tickLower (full range)
                887220, // tickUpper (full range)
                0, // minAmount0
                0, // minAmount1
                true // stake in gauge
            );
            console.log("Zapped", MICRO_DEPOSIT_VELO / 1e6, "USDT0 into Slipstream position via SlipstreamHelper");
            console.log("Position NFT tokenId:", tokenId);
            
            // Get helper address for verification
            address slipstreamHelper = vault.SLIPSTREAM_HELPER();
            console.log("SlipstreamHelper address:", slipstreamHelper);
        } else {
            console.log("SKIP: Insufficient USDT0 balance");
        }
        
        console.log("");
        
        // 6969696696969696969 TX 3: SLIPSTREAM POSITION (Direct, via SlipstreamHelper) 6969696696969696969
        console.log("420 TX 3: SLIPSTREAM POSITION (Direct, via SlipstreamHelper) 420");
        usdtBalance = IERC20(USDT0_L2).balanceOf(deployer);
        uint256 usdcBalance = IERC20(USDC_L2).balanceOf(deployer);
        console.log("Deployer USDT0 balance:", usdtBalance / 1e6);
        console.log("Deployer USDC balance:", usdcBalance / 1e6);
        
        if (usdtBalance >= MICRO_DEPOSIT_SLIPSTREAM && usdcBalance >= MICRO_DEPOSIT_SLIPSTREAM) {
            IERC20(USDT0_L2).transfer(vaultAddress, MICRO_DEPOSIT_SLIPSTREAM);
            IERC20(USDC_L2).transfer(vaultAddress, MICRO_DEPOSIT_SLIPSTREAM);
            console.log("Transferred tokens to vault");
            // Create Slipstream position directly (both tokens provided)
            // This calls SlipstreamHelper.createPosition internally
            BundledYieldVaultV2_PRODUCTION.SlipstreamMintParams memory params = 
                BundledYieldVaultV2_PRODUCTION.SlipstreamMintParams({
                    token0: USDT0_L2,
                    token1: USDC_L2,
                    fee: 100, // 0.01%
                    tickLower: -887220,
                    tickUpper: 887220,
                    amount0Desired: MICRO_DEPOSIT_SLIPSTREAM,
                    amount1Desired: MICRO_DEPOSIT_SLIPSTREAM,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 hours
                });
            
            vault.createSlipstreamPosition(params, true); // Stake immediately via SlipstreamHelper
            console.log("Created Slipstream position with", MICRO_DEPOSIT_SLIPSTREAM / 1e6, "USDT0 and USDC via SlipstreamHelper");
            
            // Get helper address for verification
            address slipstreamHelper = vault.SLIPSTREAM_HELPER();
            console.log("SlipstreamHelper address:", slipstreamHelper);
        } else {
            console.log("SKIP: Insufficient token balances");
        }
        
        console.log("");
        console.log("420 ALL MICRO TRANSACTIONS COMPLETE 420");
        console.log("Check transaction hashes above for documentation");
        
        vm.stopBroadcast();
    }
}

