// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {YieldViewer} from "../src/YieldViewer.sol";
import {BundledYieldVaultV2__MULTICALL} from "../src/BundledYieldVaultV2_PRODUCTION_MULTICALL.sol";

/// @title DeployYieldViewer
/// @notice Deploy YieldViewer contract for manual yield checking
/// @dev Run with: forge script script/DeployYieldViewer.s.sol:DeployYieldViewer --rpc-url $INK_RPC --broadcast
contract DeployYieldViewer is Script {
    // Ink L2 addresses
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    
    function run() external returns (address deployed) {
        // Get vault address from env or use default
        address vaultAddress;
        try vm.envAddress("VAULT_ADDRESS") returns (address _vault) {
            vaultAddress = _vault;
        } catch {
            revert("VAULT_ADDRESS must be set in environment");
        }
        
        // Get helper addresses from vault
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(vaultAddress);
        address slipstreamHelper = vault.SLIPSTREAM_HELPER();
        address veloHelper = vault.VELO_HELPER();
        
        console.log("=== Deploying YieldViewer ===");
        console.log("Vault Address:", vaultAddress);
        console.log("Tydro Pool:", TYDRO_POOL);
        console.log("Slipstream Helper:", slipstreamHelper);
        console.log("Velodrome Helper:", veloHelper);
        console.log("");
        
        vm.startBroadcast();
        
        YieldViewer viewer = new YieldViewer(
            vaultAddress,
            TYDRO_POOL,
            slipstreamHelper,
            veloHelper
        );
        
        vm.stopBroadcast();
        
        console.log("YieldViewer deployed at:", address(viewer));
        console.log("");
        console.log("=== Usage Examples ===");
        console.log("Get token status:");
        console.log("  viewer.getTokenStatus(tokenAddress)");
        console.log("");
        console.log("Get yield available:");
        console.log("  viewer.getYieldAvailable(tokenAddress)");
        console.log("");
        console.log("Get vault health:");
        console.log("  viewer.getVaultHealth(tokenAddress)");
        console.log("");
        console.log("Get multi-token summary:");
        console.log("  viewer.getMultiTokenSummary([token1, token2, ...])");
        console.log("");
        
        return address(viewer);
    }
}

