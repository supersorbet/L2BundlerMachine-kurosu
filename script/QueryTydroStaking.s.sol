// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {IAToken} from "../src/interfaces/ITydroAAVE.sol";
import {IL2Pool} from "../src/interfaces/IL2Pool.sol";

/**
 * @title QueryTydroStaking
 * @notice Query how much the L2 yield contract has staked in Tydro
 * @dev Run with: forge script script/QueryTydroStaking.s.sol:QueryTydroStaking --rpc-url $INK_RPC -vvvv
 */
contract QueryTydroStaking is Script {
    address constant L2_VAULT = 0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7;
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    
    function run() external view {
        console.log("=== Querying Tydro Staking Balance ===");
        console.log("L2 Vault Address:", L2_VAULT);
        console.log("Token (USDT0_L2):", USDT0_L2);
        console.log("Tydro Pool:", TYDRO_POOL);
        console.log("");
        
        BundledYieldVaultV2_PRODUCTION vault = BundledYieldVaultV2_PRODUCTION(L2_VAULT);
        
        // Get status from vault
        (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, uint256 gasBalance) = 
            vault.getStatus(USDT0_L2);
        
        console.log("--- Vault Status ---");
        console.log("Deposited Amount:", depositedAmount);
        console.log("Current Balance (in Tydro):", currentBalance);
        console.log("Yield Available:", yieldAvailable);
        console.log("Gas Balance (ETH):", gasBalance);
        console.log("");
        
        // Try to get Tydro balance directly via aToken
        try vault.getYieldAvailable(USDT0_L2) returns (uint256 yield) {
            console.log("--- Yield Available (via getYieldAvailable) ---");
            console.log("Yield:", yield);
            console.log("");
        } catch {
            console.log("Could not get yield via getYieldAvailable");
        }
        
        // Query Tydro pool directly for aToken balance
        IL2Pool pool = IL2Pool(TYDRO_POOL);
        try pool.getReserveData(USDT0_L2) returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128 variableBorrowIndex,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            uint16 id,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint128 accruedToTreasury,
            uint128 unbacked,
            uint128 isolationModeTotalDebt
        ) {
            console.log("--- Tydro Pool Reserve Data ---");
            console.log("aToken Address:", aTokenAddress);
            console.log("Liquidity Index:", liquidityIndex);
            console.log("Current Liquidity Rate:", currentLiquidityRate);
            console.log("");
            
            if (aTokenAddress != address(0)) {
                IAToken aToken = IAToken(aTokenAddress);
                uint256 aTokenBalance = aToken.balanceOf(L2_VAULT);
                console.log("--- Direct aToken Balance ---");
                console.log("aToken Balance (raw):", aTokenBalance);
                
                // Convert to USDT0 (6 decimals)
                uint256 balanceInUSDT0 = aTokenBalance / 1e12; // aToken has 18 decimals, USDT0 has 6
                console.log("Balance in USDT0:", balanceInUSDT0);
                console.log("");
            }
        } catch {
            console.log("Could not get reserve data from Tydro pool");
            console.log("Token may not be registered in Tydro");
        }
        
        // Summary
        console.log("=== Summary ===");
        console.log("Total Staked in Tydro:", currentBalance);
        console.log("Principal Deposited:", depositedAmount);
        console.log("Accumulated Yield:", yieldAvailable);
        if (currentBalance > depositedAmount) {
            console.log("Current Value:", currentBalance);
            console.log("Profit:", currentBalance - depositedAmount);
        }
    }
}

