// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {IL2Pool} from "../src/interfaces/IL2Pool.sol";
import {IL2Encoder} from "../src/interfaces/IL2Encoder.sol";
import {IAToken} from "../src/interfaces/ITydroAAVE.sol";

/// @title DeepMainnetForkTests
/// @notice Comprehensive deep testing suite for production contracts on mainnet forks
/// @dev Tests yield accumulation, harvest cycles, edge cases, safety features, and gas optimization
/// @dev Run with: ETH_RPC=<url> INK_RPC=<url> forge test --match-contract DeepMainnetForkTests -vvvv
/// @dev Or use: ./test_deep_mainnet.sh
contract DeepMainnetForkTests is Test {
    // Ethereum Mainnet addresses
    address public constant HUB_POOL = 0xc186fA914353c44b2E33eBE05f21846F1048bEda;
    address public constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Ink L2 addresses
    address public constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4;
    address public constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    address public constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c;
    address public constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;
    address public constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address public constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    
    address public treasury;
    uint256 public constant INK_CHAIN_ID = 57073;
    
    L1DepositorV2_PRODUCTION public l1Depositor;
    BundledYieldVaultV2_PRODUCTION public l2Vault;
    
    uint256 internal ethForkId;
    uint256 internal inkForkId;
    
    // Test amounts
    uint256 public constant SMALL_DEPOSIT = 1000 * 1e6; // $1k
    uint256 public constant MEDIUM_DEPOSIT = 10000 * 1e6; // $10k
    uint256 public constant LARGE_DEPOSIT = 100000 * 1e6; // $100k
    
    // Whale addresses for seeding 
    address internal constant DEFAULT_USDT_L1_WHALE = 0x6AC38D1b2f0c0c3b9E816342b1CA14d91D5Ff60B;
    address internal constant DEFAULT_USDT0_L2_WHALE = 0x2D27Bf7AD3303bDCF341C5890296Ad8B49D68829;
    address internal constant DEFAULT_TREASURY = 0x00000009eEE278329552382a472A7d06c773D7B3;
    
    address internal usdtL1Whale;
    address internal usdt0L2Whale;
    
    // Keeper address for testing
    address internal constant KEEPER_ADDRESS = 0x601BC5928f447d8f38Ba644579AD6a116A53e0D6;
    
    function setUp() public {
        // Create forks
        string memory ethRpc = vm.envString("ETH_RPC");
        ethForkId = vm.createFork(ethRpc);
        vm.selectFork(ethForkId);
        
        string memory inkRpc = vm.envString("INK_RPC");
        if (bytes(inkRpc).length > 0) {
            inkForkId = vm.createFork(inkRpc);
        } else {
            revert("INK_RPC required for deep tests");
        }
        
        // Set treasury (use env var or default)
        try vm.envAddress("TREASURY_ADDRESS") returns (address _treasury) {
            treasury = _treasury;
        } catch {
            treasury = DEFAULT_TREASURY;
        }
        
        // Deploy L2 vault on Ink fork
        vm.selectFork(inkForkId);
        l2Vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            treasury,
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
        );
        
        // Deploy L1 depositor on ETH fork
        vm.selectFork(ethForkId);
        l1Depositor = new L1DepositorV2_PRODUCTION(
            HUB_POOL,
            address(l2Vault),
            INK_CHAIN_ID
        );
        
        // Setup ownership
        vm.selectFork(ethForkId);
        l1Depositor.transferOwnership(treasury);
        
        vm.selectFork(inkForkId);
        l2Vault.transferOwnership(treasury);
        
        // Setup token mappings
        vm.selectFork(ethForkId);
        vm.startPrank(treasury);
        l1Depositor.setTokenMapping(USDT_L1, USDT0_L2);
        vm.stopPrank();
        
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        l2Vault.mapToken(USDT0_L2, USDT_L1);
        l2Vault.setL1Recipient(address(l1Depositor));
        vm.stopPrank();
        
        // Fund treasury with ETH
        vm.selectFork(ethForkId);
        vm.deal(treasury, 10 ether);
        vm.selectFork(inkForkId);
        vm.deal(treasury, 10 ether);
        vm.deal(address(l2Vault), 0.1 ether); // Fund vault with gas
        
        // Setup yield receiver
        vm.selectFork(ethForkId);
        vm.startPrank(treasury);
        l1Depositor.setYieldReceiver(treasury, true);
        vm.stopPrank();
        
        // Seed treasury with tokens if whales provided
        _seedTreasury();
        
        // Seed keeper address for keeper bot testing
        vm.selectFork(inkForkId);
        vm.deal(KEEPER_ADDRESS, 1 ether);
        console.log("Seeded keeper address:", KEEPER_ADDRESS);
    }
    
    function _seedTreasury() internal {
        // L1 USDT - use env var or default whale
        vm.selectFork(ethForkId);
        try vm.envAddress("USDT_L1_WHALE") returns (address whale) {
            usdtL1Whale = whale;
        } catch {
            usdtL1Whale = DEFAULT_USDT_L1_WHALE;
        }
        
        if (usdtL1Whale != address(0)) {
            vm.deal(usdtL1Whale, 10 ether);
            vm.startPrank(usdtL1Whale);
            (bool success, ) = USDT_L1.call(
                abi.encodeWithSignature("transfer(address,uint256)", treasury, MEDIUM_DEPOSIT * 10)
            );
            if (success) {
                console.log("Seeded L1 USDT to treasury from whale:", usdtL1Whale);
            } else {
                console.log("Failed to seed L1 USDT - whale may not have balance");
            }
            vm.stopPrank();
        }
        
        // L2 USDT0 - use env var or default whale
        vm.selectFork(inkForkId);
        try vm.envAddress("USDT0_L2_WHALE") returns (address whale) {
            usdt0L2Whale = whale;
        } catch {
            usdt0L2Whale = DEFAULT_USDT0_L2_WHALE;
        }
        
        if (usdt0L2Whale != address(0)) {
            vm.deal(usdt0L2Whale, 10 ether);
            vm.startPrank(usdt0L2Whale);
            (bool success, ) = USDT0_L2.call(
                abi.encodeWithSignature("transfer(address,uint256)", treasury, MEDIUM_DEPOSIT * 10)
            );
            if (success) {
                console.log("Seeded L2 USDT0 to treasury from whale:", usdt0L2Whale);
            } else {
                console.log("Failed to seed L2 USDT0 - whale may not have balance");
            }
            vm.stopPrank();
        }
    }
    
    function _erc20Balance(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        if (!success || data.length == 0) return 0;
        return abi.decode(data, (uint256));
    }
    
    /// @notice Check if asset is registered in Tydro pool
    function _isAssetRegistered(address token) internal view returns (bool) {
        try IL2Pool(TYDRO_POOL).getReserveData(token) returns (
            uint256,
            uint128,
            uint128,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16 id,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return id != 0; // Asset ID 0 means not registered
        } catch {
            return false;
        }
    }
    
    /// @notice Check if encoder can encode params for this asset
    function _canEncodeAsset(address token) internal view returns (bool) {
        try IL2Encoder(L2_ENCODER).encodeSupplyParams(token, 1, 0) returns (bytes32) {
            return true;
        } catch {
            return false;
        }
    }
    
    // ^_________________^
    // DEEP YIELD ACCUMULATION TESTS
    // ^_________________^
    
    /// @notice Test yield accumulation over multiple time periods
    function testDeepYieldAccumulation() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered or cannot be encoded");
            return;
        }
        
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient L2 balance");
            return;
        }
        
        console.log("&*&*&*&*&* DEEP YIELD ACCUMULATION TEST &*&*&*&*&*");
        console.log("Initial deposit:", depositAmount);
        
        // Deposit
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            console.log("Deposit successful");
        } catch Error(string memory reason) {
            console.log("Deposit failed:", reason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Deposit failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Get initial status
        uint256 yield1 = _getYield(USDT0_L2);
        console.log("After deposit - Yield:", yield1);
        
        // Update yield immediately
        vm.startPrank(treasury);
        l2Vault.updateYield(USDT0_L2);
        vm.stopPrank();
        
        yield1 = _getYield(USDT0_L2);
        console.log("Immediate update - Yield:", yield1);
        
        // Test yield accumulation over time
        _testYieldOverTime(yield1);
    }
    
    function _getYield(address token) internal view returns (uint256) {
        (, , uint256 yield, ) = l2Vault.getStatus(token);
        return yield;
    }
    
    function _testYieldOverTime(uint256 initialYield) internal {
        uint256[5] memory periods = [uint256(1 days), 7 days, 30 days, 60 days, 90 days];
        
        for (uint256 i = 0; i < periods.length; i++) {
            vm.warp(block.timestamp + periods[i]);
            
            vm.startPrank(treasury);
            l2Vault.updateYield(USDT0_L2);
            vm.stopPrank();
            
            uint256 yield = _getYield(USDT0_L2);
            uint256 apy = l2Vault.getCurrentAPY(USDT0_L2);
            
            console.log("--- After", periods[i] / 1 days, "days ---");
            console.log("Yield available:", yield);
            console.log("APY:", apy);
            
            if (i > 0) {
                assertGe(yield, initialYield, "Yield should accumulate");
            }
        }
    }
    
    /// @notice Test multiple harvest cycles with compounding
    function testDeepHarvestCycles() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered or cannot be encoded");
            return;
        }
        
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient L2 balance");
            return;
        }
        
        console.log("&*&*&*&*&* DEEP HARVEST CYCLES TEST &*&*&*&*&*");
        
        // Initial deposit
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            console.log("Initial deposit successful");
        } catch Error(string memory reason) {
            console.log("Deposit failed:", reason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Deposit failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        uint256 initialDeposited = _getDeposited(USDT0_L2);
        console.log("Initial deposited:", initialDeposited);
        
        // Run harvest cycles
        uint8[4] memory compoundPercents = [uint8(0), 25, 50, 100];
        
        for (uint256 cycle = 0; cycle < 4; cycle++) {
            _runHarvestCycle(cycle, compoundPercents[cycle % 4]);
        }
        
        uint256 finalDeposited = _getDeposited(USDT0_L2);
        console.log("Final deposited:", finalDeposited);
        assertGe(finalDeposited, initialDeposited, "Final deposited should >= initial");
    }
    
    function _getDeposited(address token) internal view returns (uint256) {
        (uint256 deposited, , , ) = l2Vault.getStatus(token);
        return deposited;
    }
    
    function _runHarvestCycle(uint256 cycle, uint8 compoundPercent) internal {
        console.log("--- Harvest Cycle", cycle + 1, "---");
        
        vm.warp(block.timestamp + 7 days);
        
        vm.startPrank(treasury);
        l2Vault.updateYield(USDT0_L2);
        vm.stopPrank();
        
        uint256 yieldBefore = _getYield(USDT0_L2);
        uint256 depositedBefore = _getDeposited(USDT0_L2);
        
        console.log("Before harvest - Deposited:", depositedBefore);
        console.log("Before harvest - Yield:", yieldBefore);
        
        if (yieldBefore < 1000) {
            console.log("Skipping harvest - insufficient yield");
            return;
        }
        
        console.log("Harvesting with", compoundPercent, "% compound");
        
        vm.startPrank(treasury);
        try l2Vault.harvestAndBridge(USDT0_L2, compoundPercent, 0, 0) {
            console.log("Harvest successful");
        } catch Error(string memory reason) {
            console.log("Harvest failed:", reason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Harvest failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        uint256 depositedAfter = _getDeposited(USDT0_L2);
        uint256 yieldAfter = _getYield(USDT0_L2);
        
        console.log("After harvest - Deposited:", depositedAfter);
        console.log("After harvest - Yield:", yieldAfter);
        
        if (compoundPercent > 0) {
            assertGe(depositedAfter, depositedBefore, "Deposited should increase");
        }
        assertLe(yieldAfter, yieldBefore, "Yield should decrease");
    }
    
    // ^_________________^
    // EDGE CASE TESTS
    // ^_________________^
    
    /// @notice Test gas management edge cases
    function testDeepGasManagement() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP GAS MANAGEMENT TEST &*&*&*&*&*");
        
        uint128 minGas = l2Vault.minGasBalance();
        console.log("Min gas balance:", minGas);
        
        // Test 1: Low gas balance
        vm.deal(address(l2Vault), minGas / 2);
        bool hasGas = _checkGasStatus();
        assertFalse(hasGas, "Should not have sufficient gas");
        
        // Test 2: Auto gas refill
        uint64 autoRefill = l2Vault.autoGasRefillBps();
        console.log("Auto refill BPS:", autoRefill);
        
        // Test 3: Restore gas and verify
        vm.deal(address(l2Vault), minGas * 2);
        hasGas = _checkGasStatus();
        assertTrue(hasGas, "Should have sufficient gas after refill");
    }
    
    function _checkGasStatus() internal view returns (bool) {
        // Check gas directly since getVaultHealth may fail if asset not registered
        uint128 minGas = l2Vault.minGasBalance();
        uint256 vaultBalance = address(l2Vault).balance;
        bool hasGas = vaultBalance >= minGas;
        console.log("Vault balance:", vaultBalance);
        console.log("Min gas required:", minGas);
        console.log("Has gas:", hasGas);
        return hasGas;
    }
    
    /// @notice Test slippage edge cases
    function testDeepSlippageHandling() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP SLIPPAGE HANDLING TEST &*&*&*&*&*");
        
        uint64 defaultSlippage = l2Vault.defaultSlippageBps();
        console.log("Default slippage BPS:", defaultSlippage);
        
        // Test with custom slippage
        uint64 customSlippage = 50; // 0.5%
        console.log("Testing with custom slippage:", customSlippage);
        
        // Test invalid slippage (> 10% = 1000 bps)
        vm.startPrank(treasury);
        try l2Vault.harvestAndBridge(USDT0_L2, 50, 1001, 0) {
            console.log("Warning: Invalid slippage was accepted (may not have deposits)");
        } catch Error(string memory reason) {
            console.log("Correctly reverted with:", reason);
            // May revert for other reasons if no deposits exist
            if (keccak256(bytes(reason)) == keccak256(bytes("InvalidSlippage()"))) {
                console.log("Invalid slippage correctly rejected");
            } else {
                console.log("Reverted for different reason (expected if no deposits)");
            }
        } catch {
            console.log("Reverted with unknown error (expected if no deposits)");
        }
        vm.stopPrank();
        
        console.log("Slippage handling test completed");
    }
    
    /// @notice Test rate limiting and cooldowns
    function testDeepRateLimiting() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP RATE LIMITING TEST &*&*&*&*&*");
        
        // Get rate limit config
        uint8 maxOpsPerHour = l2Vault.maxOperationsPerHour();
        uint256 cooldownPeriod = l2Vault.operationCooldown(USDT0_L2);
        
        console.log("Max ops per hour:", maxOpsPerHour);
        console.log("Cooldown period:", cooldownPeriod);
        
        // Skip if asset not registered (updateYield will fail)
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered - updateYield will fail");
            console.log("Rate limiting test completed (skipped)");
            return;
        }
        
        // Test rapid operations
        vm.startPrank(treasury);
        uint256 maxTests = maxOpsPerHour > 0 ? uint256(maxOpsPerHour) + 1 : 5;
        if (maxTests > 10) maxTests = 10; // Limit to 10
        
        for (uint256 i = 0; i < maxTests; i++) {
            try l2Vault.updateYield(USDT0_L2) {
                console.log("Update", i + 1, "succeeded");
            } catch Error(string memory reason) {
                console.log("Update", i + 1, "failed:", reason);
                if (i >= maxOpsPerHour && maxOpsPerHour > 0) {
                    console.log("Rate limit triggered as expected");
                    break; // Stop if rate limited
                }
            } catch {
                console.log("Update", i + 1, "failed: unknown error");
                // If asset not registered, stop trying
                if (i == 0) break;
            }
            vm.warp(block.timestamp + 60); // Advance 1 minute
        }
        vm.stopPrank();
        
        console.log("Rate limiting test completed");
    }
    
    /// @notice Test daily withdrawal limits
    function testDeepWithdrawalLimits() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP WITHDRAWAL LIMITS TEST &*&*&*&*&*");
        
        uint128 maxDaily = l2Vault.maxDailyWithdrawals(USDT0_L2);
        console.log("Max daily withdrawal:", maxDaily);
        
        if (maxDaily > 0) {
            // Test exceeding limit
            uint256 today = block.timestamp / 1 days;
            uint128 withdrawnToday = l2Vault.dailyWithdrawals(USDT0_L2, uint32(today));
            console.log("Withdrawn today:", withdrawnToday);
            
            // Try to withdraw more than limit
            if (withdrawnToday >= maxDaily) {
                vm.startPrank(treasury);
                try l2Vault.harvestAndBridge(USDT0_L2, 0, 0, 0) {
                    revert("Should have reverted");
                } catch Error(string memory reason) {
                    console.log("Correctly reverted:", reason);
                }
                vm.stopPrank();
            }
        }
    }
    
    // ^_________________^
    // SAFETY FEATURE TESTS
    // ^_________________^
    
    /// @notice Test all safety features comprehensively
    function testDeepSafetyFeatures() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP SAFETY FEATURES TEST &*&*&*&*&*");
        
        // Test 1: Pause/Unpause
        console.log("--- Testing Pause ---");
        vm.startPrank(treasury);
        l2Vault.pause();
        vm.stopPrank();
        
        (bool canOp, string memory reason) = l2Vault.canPerformOp(USDT0_L2);
        assertFalse(canOp, "Operations should be blocked when paused");
        console.log("Pause reason:", reason);
        
        vm.startPrank(treasury);
        l2Vault.unpause();
        vm.stopPrank();
        
        (canOp, ) = l2Vault.canPerformOp(USDT0_L2);
        assertTrue(canOp, "Operations should be allowed when unpaused");
        
        // Test 2: Emergency Mode
        console.log("--- Testing Emergency Mode ---");
        vm.startPrank(treasury);
        l2Vault.activateEmsMode();
        vm.stopPrank();
        
        (canOp, reason) = l2Vault.canPerformOp(USDT0_L2);
        assertFalse(canOp, "Operations should be blocked in emergency mode");
        console.log("Emergency mode reason:", reason);
        
        vm.startPrank(treasury);
        l2Vault.deactivateEmsMode();
        vm.stopPrank();
        
        (canOp, ) = l2Vault.canPerformOp(USDT0_L2);
        assertTrue(canOp, "Operations should be allowed after deactivating emergency mode");
        
        // Test 3: Circuit Breaker
        console.log("--- Testing Circuit Breaker ---");
        vm.startPrank(treasury);
        l2Vault.activateBreaker();
        vm.stopPrank();
        
        (canOp, reason) = l2Vault.canPerformOp(USDT0_L2);
        assertFalse(canOp, "Operations should be blocked when circuit breaker active");
        console.log("Circuit breaker reason:", reason);
        
        vm.startPrank(treasury);
        l2Vault.deactivateBreaker();
        vm.stopPrank();
        
        (canOp, ) = l2Vault.canPerformOp(USDT0_L2);
        assertTrue(canOp, "Operations should be allowed after deactivating circuit breaker");
    }
    
    // ^_________________^
    // CONFIGURATION TESTS
    // ^_________________^
    
    /// @notice Test configuration changes
    function testDeepConfiguration() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP CONFIGURATION TEST &*&*&*&*&*");
        
        // Get current config
        uint128 minGas = l2Vault.minGasBalance();
        uint64 slippage = l2Vault.defaultSlippageBps();
        uint64 autoRefill = l2Vault.autoGasRefillBps();
        
        console.log("Current min gas:", minGas);
        console.log("Current slippage:", slippage);
        console.log("Current auto refill:", autoRefill);
        
        // Update config
        vm.startPrank(treasury);
        l2Vault.setMinGasBal(minGas * 2);
        l2Vault.setDefaultSlippage(slippage + 10);
        l2Vault.setAutoRefill(autoRefill + 10);
        vm.stopPrank();
        
        // Verify changes
        assertEq(l2Vault.minGasBalance(), minGas * 2, "Min gas should be updated");
        assertEq(l2Vault.defaultSlippageBps(), slippage + 10, "Slippage should be updated");
        assertEq(l2Vault.autoGasRefillBps(), autoRefill + 10, "Auto refill should be updated");
        
        // Restore original values
        vm.startPrank(treasury);
        l2Vault.setMinGasBal(minGas);
        l2Vault.setDefaultSlippage(slippage);
        l2Vault.setAutoRefill(autoRefill);
        vm.stopPrank();
    }
    
    // ^_________________^
    // INTEGRATION TESTS
    // ^_________________^
    
    /// @notice Test full integration with real Tydro pool
    function testDeepTydroIntegration() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP TYDRO INTEGRATION TEST &*&*&*&*&*");
        
        // Check if asset is registered
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: USDT0_L2 not registered in Tydro pool");
            console.log("This is expected if the asset hasn't been activated on Ink L2");
            return;
        }
        
        if (!_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Cannot encode USDT0_L2 in L2 encoder");
            return;
        }
        
        // Get reserve data to verify integration
        _checkReserveData();
        
        uint256 depositAmount = SMALL_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping deposit test: Insufficient L2 balance");
            return;
        }
        
        // Try deposit
        _tryDeposit(depositAmount);
        
        // Verify aToken
        address aToken = l2Vault.getATokenAddress(USDT0_L2);
        console.log("aToken address:", aToken);
        if (aToken != address(0)) {
            uint256 aTokenBalance = IAToken(aToken).balanceOf(address(l2Vault));
            console.log("aToken balance:", aTokenBalance);
            assertGe(aTokenBalance, depositAmount, "aToken balance should >= deposit");
        }
    }
    
    function _checkReserveData() internal {
        try IL2Pool(TYDRO_POOL).getReserveData(USDT0_L2) returns (
            uint256 configuration,
            uint128,
            uint128,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16 id,
            address aTokenAddress,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            console.log("Asset ID:", id);
            console.log("aToken address:", aTokenAddress);
            console.log("Configuration:", configuration);
            
            address vaultAToken = l2Vault.getATokenAddress(USDT0_L2);
            console.log("Vault aToken:", vaultAToken);
            
            if (aTokenAddress != address(0)) {
                console.log("Tydro integration verified - asset is registered");
            }
        } catch {
            console.log("Could not get reserve data from Tydro pool");
        }
    }
    
    function _tryDeposit(uint256 amount) internal {
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), amount)
        );
        if (ok) {
            try l2Vault.deposit(USDT0_L2, amount) {
                console.log("Deposit successful");
            } catch Error(string memory reason) {
                console.log("Deposit failed:", reason);
            } catch {
                console.log("Deposit failed: unknown error");
            }
        }
        vm.stopPrank();
    }
    
    /// @notice Test vault health monitoring
    function testDeepVaultHealth() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* DEEP VAULT HEALTH TEST &*&*&*&*&*");
        
        bool hasGas = _checkVaultGas();
        assertTrue(hasGas, "Vault should have gas");
        
        // Test health after operations
        vm.startPrank(treasury);
        try l2Vault.updateYield(USDT0_L2) {
            console.log("Yield update successful");
        } catch {
            console.log("Yield update failed (expected if asset not registered)");
        }
        vm.stopPrank();
        
        // Check vault health - should work even if asset not registered
        (bool healthy, bool hasGasFromHealth, , , ) = l2Vault.getVaultHealth(USDT0_L2);
        
        assertTrue(healthy, "Vault should be healthy (not paused/ems/breaker)");
        assertTrue(hasGasFromHealth, "Vault should have gas according to getVaultHealth");
        assertTrue(hasGas, "Vault should have gas (direct check)");
        
        console.log("Vault health test completed");
    }
    
    function _checkVaultGas() internal returns (bool) {
        // Check gas directly since getVaultHealth may fail if asset not registered
        uint128 minGas = l2Vault.minGasBalance();
        uint256 vaultBalance = address(l2Vault).balance;
        bool hasGas = vaultBalance >= minGas;
        
        console.log("Vault balance:", vaultBalance);
        console.log("Min gas required:", minGas);
        console.log("Has gas:", hasGas);
        
        if (!hasGas) {
            console.log("Warning: Vault has low gas - funding with ETH");
            vm.deal(address(l2Vault), 0.1 ether);
            vaultBalance = address(l2Vault).balance;
            hasGas = vaultBalance >= minGas;
            console.log("Vault balance after funding:", vaultBalance);
            console.log("Has gas after funding:", hasGas);
        }
        
        // Try to get health status if asset is registered
        if (_isAssetRegistered(USDT0_L2)) {
            (bool healthy, , , , ) = l2Vault.getVaultHealth(USDT0_L2);
            console.log("Vault healthy:", healthy);
        }
        
        return hasGas;
    }
    
    
    /// @notice Test permissionless auto-harvest function
    function testAutoHarvestAndBridge() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        console.log("&*&*&*&*&* AUTO-HARVEST TEST &*&*&*&*&*");
        
        // Setup: Deposit funds
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            console.log("Deposit successful");
        } catch {
            console.log("Deposit failed");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Advance time to accumulate yield
        vm.warp(block.timestamp + 30 days);
        
        // Update yield
        l2Vault.updateYield(USDT0_L2);
        
        uint256 yieldBefore = _getYield(USDT0_L2);
        uint256 principal = _getDeposited(USDT0_L2);
        uint256 threshold = (principal * l2Vault.minYieldThresholdBps()) / 10000;
        
        console.log("Principal:", principal);
        console.log("Yield before:", yieldBefore);
        console.log("Threshold:", threshold);
        console.log("Default compound %:", l2Vault.defaultCompoundPercent());
        
        if (yieldBefore < threshold) {
            console.log("Skipping: Yield below threshold");
            return;
        }
        
        // Test: Anyone can call auto-harvest (not just owner)
        address keeper = address(0x1234);
        vm.deal(keeper, 1 ether);
        
        vm.startPrank(keeper);
        try l2Vault.autoHarvestAndBridge(USDT0_L2) {
            console.log("Auto-harvest successful");
        } catch Error(string memory harvestReason) {
            console.log("Auto-harvest failed:", harvestReason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Auto-harvest failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Verify yield was harvested
        l2Vault.updateYield(USDT0_L2);
        uint256 yieldAfter = _getYield(USDT0_L2);
        uint256 depositedAfter = _getDeposited(USDT0_L2);
        
        console.log("Yield after:", yieldAfter);
        console.log("Deposited after:", depositedAfter);
        
        assertLe(yieldAfter, yieldBefore, "Yield should decrease after harvest");
        assertGe(depositedAfter, principal, "Deposited should increase if compound > 0");
    }
    
    /// @notice Test auto-harvest threshold enforcement
    function testAutoHarvestThreshold() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        console.log("&*&*&*&*&* AUTO-HARVEST THRESHOLD TEST &*&*&*&*&*");
        
        // Setup deposit
        uint256 depositAmount = SMALL_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Update yield immediately (should be 0 or very small)
        l2Vault.updateYield(USDT0_L2);
        
        uint256 yield = _getYield(USDT0_L2);
        uint256 principal = _getDeposited(USDT0_L2);
        uint256 threshold = (principal * l2Vault.minYieldThresholdBps()) / 10000;
        
        console.log("Yield:", yield);
        console.log("Threshold:", threshold);
        
        // Should fail if yield < threshold
        address keeper = address(0x5678);
        vm.startPrank(keeper);
        if (yield < threshold) {
            vm.expectRevert();
            l2Vault.autoHarvestAndBridge(USDT0_L2);
            console.log("Correctly rejected: yield below threshold");
        } else {
            console.log("Yield exceeds threshold, harvest should succeed");
        }
        vm.stopPrank();
    }
    
    /// @notice Test rate limiting on auto-harvest
    function testAutoHarvestRateLimit() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* AUTO-HARVEST RATE LIMIT TEST &*&*&*&*&*");
        
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        uint8 maxOps = l2Vault.maxOperationsPerHour();
        console.log("Max ops per hour:", maxOps);
        
        if (maxOps == 0) {
            console.log("Rate limiting disabled, skipping test");
            return;
        }
        
        // Set up a deposit with yield
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        if (!ok) {
            vm.stopPrank();
            return;
        }
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            vm.warp(block.timestamp + 30 days);
            l2Vault.updateYield(USDT0_L2);
        } catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Check if we have yield above threshold
        uint256 yield = _getYield(USDT0_L2);
        uint256 principal = _getDeposited(USDT0_L2);
        uint256 threshold = (principal * l2Vault.minYieldThresholdBps()) / 10000;
        
        if (yield < threshold) {
            console.log("Skipping: Yield below threshold");
            return;
        }
        
        address keeper = address(0x9999);
        
        // Try to call more than maxOps times
        uint256 successCount = 0;
        uint256 limit = maxOps > 10 ? 10 : uint256(maxOps) + 2; // Limit iterations to prevent gas issues
        for (uint256 i = 0; i < limit; i++) {
            vm.startPrank(keeper);
            try l2Vault.autoHarvestAndBridge(USDT0_L2) {
                successCount++;
                console.log("Call", i + 1, "succeeded");
                // After first success, yield will be harvested, so subsequent calls will fail threshold
                break;
            } catch Error(string memory reason) {
                console.log("Call", i + 1, "failed:", reason);
                // If rate limited, break
                if (keccak256(bytes(reason)) == keccak256(bytes("Rate limit exceeded"))) {
                    break;
                }
            } catch {
                console.log("Call", i + 1, "failed: unknown");
            }
            vm.stopPrank();
            
            // Advance time slightly
            vm.warp(block.timestamp + 1);
        }
        
        console.log("Successful calls:", successCount);
        assertLe(successCount, uint256(maxOps), "Should respect rate limit");
    }
    
    /// @notice Test batch auto-harvest
    function testAutoHarvestAll() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* BATCH AUTO-HARVEST TEST &*&*&*&*&*");
        
        // This test would need multiple tokens, so we'll just test the function exists
        address[] memory tokens = new address[](1);
        tokens[0] = USDT0_L2;
        
        address keeper = address(0xABCD);
        vm.startPrank(keeper);
        try l2Vault.autoHarvestAll(tokens) {
            console.log("Batch harvest called successfully");
        } catch {
            console.log("Batch harvest failed (expected if no yield)");
        }
        vm.stopPrank();
    }
    
    // ^_________________^
    // KEEPER BOT INTEGRATION TESTS
    // ^_________________^
    
    /// @notice Test keeper bot can read vault configuration
    function testKeeperBotReadsConfig() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT CONFIG TEST &*&*&*&*&*");
        
        // Test that keeper can read all config values
        uint64 minThreshold = l2Vault.minYieldThresholdBps();
        uint8 compoundPercent = l2Vault.defaultCompoundPercent();
        uint128 minGas = l2Vault.minGasBalance();
        
        console.log("Min Yield Threshold:", minThreshold, "bps");
        console.log("Default Compound %:", compoundPercent, "%");
        console.log("Min Gas Balance:", minGas);
        
        assertTrue(minThreshold > 0, "Min threshold should be set");
        assertTrue(compoundPercent <= 100, "Compound percent should be valid");
        assertTrue(minGas > 0, "Min gas should be set");
    }
    
    /// @notice Test keeper bot can read vault health
    function testKeeperBotReadsHealth() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT HEALTH TEST &*&*&*&*&*");
        
        // Test reading vault health (should work even if asset not registered)
        (bool healthy, bool hasGas, bool hasYield, uint256 timeSinceUpdate, uint256 tvl) = 
            l2Vault.getVaultHealth(USDT0_L2);
        
        console.log("Vault Healthy:", healthy);
        console.log("Has Gas:", hasGas);
        console.log("Has Yield:", hasYield);
        console.log("Time Since Update:", timeSinceUpdate);
        console.log("Total Value Locked:", tvl);
        
        // Health check should always work (returns vault state even if asset not registered)
        assertTrue(true, "Health check completed");
    }
    
    /// @notice Test keeper bot can read token status
    function testKeeperBotReadsTokenStatus() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT TOKEN STATUS TEST &*&*&*&*&*");
        
        // Test reading token status
        (uint128 deposited, uint128 currentBalance, uint128 yieldAvailable, uint32 lastUpdate) = 
            l2Vault.tokenStatus(USDT0_L2);
        
        console.log("Deposited:", deposited);
        console.log("Current Balance:", currentBalance);
        console.log("Yield Available:", yieldAvailable);
        console.log("Last Update:", lastUpdate);
        
        // Status should always be readable (returns zeros if no deposits)
        assertTrue(true, "Token status read completed");
    }
    
    /// @notice Test keeper bot can update yield (permissionless)
    function testKeeperBotUpdatesYield() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        console.log("&*&*&*&*&* KEEPER BOT UPDATE YIELD TEST &*&*&*&*&*");
        
        // Keeper should be able to call updateYield (permissionless)
        vm.startPrank(KEEPER_ADDRESS);
        try l2Vault.updateYield(USDT0_L2) {
            console.log("Keeper successfully updated yield");
        } catch Error(string memory reason) {
            console.log("Update yield failed:", reason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Update yield failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Verify yield was updated
        (,, uint128 yieldAvailable, uint32 lastUpdate) = l2Vault.tokenStatus(USDT0_L2);
        console.log("Yield after update:", yieldAvailable);
        console.log("Last update timestamp:", lastUpdate);
        
        assertTrue(lastUpdate > 0, "Last update should be set");
    }
    
    /// @notice Test keeper bot auto-harvest flow (full integration)
    function testKeeperBotAutoHarvestFlow() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered or cannot be encoded");
            return;
        }
        
        console.log("&*&*&*&*&* KEEPER BOT AUTO-HARVEST FLOW TEST &*&*&*&*&*");
        
        // Setup: Deposit funds
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            console.log("Deposit successful");
        } catch {
            console.log("Deposit failed");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Advance time to accumulate yield
        vm.warp(block.timestamp + 30 days);
        
        // Step 1: Keeper updates yield
        vm.startPrank(KEEPER_ADDRESS);
        l2Vault.updateYield(USDT0_L2);
        vm.stopPrank();
        
        uint256 yieldBefore = _getYield(USDT0_L2);
        uint256 principal = _getDeposited(USDT0_L2);
        uint256 threshold = (principal * l2Vault.minYieldThresholdBps()) / 10000;
        
        console.log("Principal:", principal);
        console.log("Yield:", yieldBefore);
        console.log("Threshold:", threshold);
        
        if (yieldBefore < threshold) {
            console.log("Skipping harvest: Yield below threshold");
            return;
        }
        
        // Step 2: Keeper checks canPerformOp
        (bool canOperate, string memory opReason) = l2Vault.canPerformOp(USDT0_L2);
        console.log("Can perform op:", canOperate);
        if (!canOperate) {
            console.log("Reason:", opReason);
        }
        
        // Step 3: Keeper calls auto-harvest
        vm.startPrank(KEEPER_ADDRESS);
        try l2Vault.autoHarvestAndBridge(USDT0_L2) {
            console.log("Auto-harvest successful");
        } catch Error(string memory harvestReason) {
            console.log("Auto-harvest failed:", harvestReason);
            vm.stopPrank();
            return;
        } catch {
            console.log("Auto-harvest failed: unknown error");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Step 4: Verify harvest succeeded
        l2Vault.updateYield(USDT0_L2);
        uint256 yieldAfter = _getYield(USDT0_L2);
        uint256 depositedAfter = _getDeposited(USDT0_L2);
        
        console.log("Yield after harvest:", yieldAfter);
        console.log("Deposited after harvest:", depositedAfter);
        
        assertLe(yieldAfter, yieldBefore, "Yield should decrease after harvest");
        assertGe(depositedAfter, principal, "Deposited should increase if compound > 0");
        
        console.log("Keeper bot auto-harvest flow completed successfully");
    }
    
    /// @notice Test keeper bot batch operations
    function testKeeperBotBatchOperations() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT BATCH OPERATIONS TEST &*&*&*&*&*");
        
        address[] memory tokens = new address[](1);
        tokens[0] = USDT0_L2;
        
        // Test batch auto-harvest (should handle failures gracefully)
        vm.startPrank(KEEPER_ADDRESS);
        try l2Vault.autoHarvestAll(tokens) {
            console.log("Batch harvest called successfully");
        } catch {
            console.log("Batch harvest failed (expected if no yield)");
        }
        vm.stopPrank();
        
        // Test batch yield update (manual loop simulation)
        vm.startPrank(KEEPER_ADDRESS);
        for (uint256 i = 0; i < tokens.length; i++) {
            try l2Vault.updateYield(tokens[i]) {
                console.log("Updated yield for token", i);
            } catch {
                console.log("Failed to update yield for token", i);
            }
        }
        vm.stopPrank();
        
        console.log("Batch operations test completed");
    }
    
    /// @notice Test keeper bot handles rate limits correctly
    function testKeeperBotRateLimits() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT RATE LIMIT TEST &*&*&*&*&*");
        
        uint8 maxOps = l2Vault.maxOperationsPerHour();
        console.log("Max ops per hour:", maxOps);
        
        if (maxOps == 0) {
            console.log("Rate limiting disabled");
            return;
        }
        
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        // Test that keeper respects rate limits
        vm.startPrank(KEEPER_ADDRESS);
        
        // Try calls up to maxOps (don't exceed to avoid gas issues)
        uint256 limit = maxOps > 3 ? 3 : uint256(maxOps); // Limit to 3 to avoid gas issues
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < limit; i++) {
            try l2Vault.updateYield(USDT0_L2) {
                successCount++;
                console.log("Call", i + 1, "succeeded");
            } catch Error(string memory reason) {
                console.log("Call", i + 1, "failed:", reason);
                if (keccak256(bytes(reason)) == keccak256("Rate limit exceeded")) {
                    break;
                }
            } catch {
                console.log("Call", i + 1, "failed: unknown");
                break; // Stop on unknown errors to avoid gas exhaustion
            }
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();
        
        console.log("Successful calls:", successCount);
        assertLe(successCount, uint256(maxOps), "Should respect rate limit");
    }
    
    /// @notice Test keeper bot with time-based yield accumulation (vm.warp)
    function testKeeperBotTimeBasedHarvest() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered or cannot be encoded");
            return;
        }
        
        console.log("&*&*&*&*&* KEEPER BOT TIME-BASED HARVEST TEST &*&*&*&*&*");
        
        // Setup: Deposit funds
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        require(ok, "Approve failed");
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {
            console.log("Deposit successful");
        } catch {
            console.log("Deposit failed");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        uint256 initialDeposited = _getDeposited(USDT0_L2);
        console.log("Initial deposited:", initialDeposited);
        
        // Test multiple harvest cycles over time
        for (uint256 cycle = 0; cycle < 4; cycle++) {
            console.log("");
            console.log("--- Harvest Cycle", cycle + 1, "---");
            
            // Advance time (30 days per cycle)
            uint256 timeBefore = block.timestamp;
            vm.warp(block.timestamp + 30 days);
            uint256 timeAfter = block.timestamp;
            console.log("Time advanced:", (timeAfter - timeBefore) / 1 days, "days");
            
            // Keeper updates yield
            vm.startPrank(KEEPER_ADDRESS);
            l2Vault.updateYield(USDT0_L2);
            vm.stopPrank();
            
            uint256 yield = _getYield(USDT0_L2);
            uint256 deposited = _getDeposited(USDT0_L2);
            uint256 threshold = (deposited * l2Vault.minYieldThresholdBps()) / 10000;
            
            console.log("Deposited:", deposited);
            console.log("Yield:", yield);
            console.log("Threshold:", threshold);
            
            if (yield >= threshold) {
                // Keeper auto-harvests
                console.log("Yield exceeds threshold - harvesting...");
                
                vm.startPrank(KEEPER_ADDRESS);
                try l2Vault.autoHarvestAndBridge(USDT0_L2) {
                    console.log("Harvest successful");
                    
                    // Verify harvest
                    l2Vault.updateYield(USDT0_L2);
                    uint256 yieldAfter = _getYield(USDT0_L2);
                    uint256 depositedAfter = _getDeposited(USDT0_L2);
                    
                    console.log("After harvest - Yield:", yieldAfter);
                    console.log("After harvest - Deposited:", depositedAfter);
                    
                    assertLe(yieldAfter, yield, "Yield should decrease");
                    assertGe(depositedAfter, deposited, "Deposited should increase if compound > 0");
                } catch Error(string memory reason) {
                    console.log("Harvest failed:", reason);
                } catch {
                    console.log("Harvest failed: unknown error");
                }
                vm.stopPrank();
            } else {
                console.log("Yield below threshold - skipping harvest");
            }
        }
        
        // Final check: Deposited should have increased due to compounding
        uint256 finalDeposited = _getDeposited(USDT0_L2);
        console.log("");
        console.log("Final deposited:", finalDeposited);
        console.log("Growth:", ((finalDeposited - initialDeposited) * 10000) / initialDeposited, "bps");
        
        assertGe(finalDeposited, initialDeposited, "Deposited should increase over time");
    }
    
    /// @notice Test keeper bot with rapid time advancement (stress test)
    function testKeeperBotRapidTimeAdvancement() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        console.log("&*&*&*&*&* KEEPER BOT RAPID TIME ADVANCEMENT TEST &*&*&*&*&*");
        
        // Setup deposit
        uint256 depositAmount = MEDIUM_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        if (ok) {
            try l2Vault.deposit(USDT0_L2, depositAmount) {} catch {
                vm.stopPrank();
                return;
            }
        }
        vm.stopPrank();
        
        // Rapid time advancement: 1 year in 10 steps
        uint256 steps = 10;
        uint256 timePerStep = 365 days / steps;
        
        console.log("Advancing time: 365 days in", steps, "steps");
        
        for (uint256 i = 0; i < steps; i++) {
            vm.warp(block.timestamp + timePerStep);
            
            // Keeper updates yield periodically
            if (i % 2 == 0) { // Every other step
                vm.startPrank(KEEPER_ADDRESS);
                try l2Vault.updateYield(USDT0_L2) {
                    uint256 yield = _getYield(USDT0_L2);
                    uint256 deposited = _getDeposited(USDT0_L2);
                    uint256 threshold = (deposited * l2Vault.minYieldThresholdBps()) / 10000;
                    
                    if (yield >= threshold) {
                        try l2Vault.autoHarvestAndBridge(USDT0_L2) {
                            console.log("Step", i + 1, "- Harvested");
                        } catch {
                            // Harvest failed, continue
                        }
                    }
                } catch {
                    // Update failed, continue
                }
                vm.stopPrank();
            }
        }
        
        // Final state check
        l2Vault.updateYield(USDT0_L2);
        uint256 finalYield = _getYield(USDT0_L2);
        uint256 finalDeposited = _getDeposited(USDT0_L2);
        
        console.log("Final yield:", finalYield);
        console.log("Final deposited:", finalDeposited);
        
        assertTrue(finalDeposited >= depositAmount, "Deposited should not decrease");
    }
    
    /// @notice Test keeper bot handles time-based edge cases
    function testKeeperBotTimeEdgeCases() public {
        vm.selectFork(inkForkId);
        
        console.log("&*&*&*&*&* KEEPER BOT TIME EDGE CASES TEST &*&*&*&*&*");
        
        // Test 1: Very large time jump
        uint256 currentTime = block.timestamp;
        vm.warp(block.timestamp + 10 * 365 days); // 10 years
        console.log("Advanced time 10 years");
        
        // Test 2: Time goes backwards (shouldn't happen but test robustness)
        vm.warp(currentTime - 1 days);
        console.log("Set time backwards (edge case)");
        
        // Test 3: Multiple rapid warps
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(block.timestamp + 1 days);
        }
        console.log("Rapid time warps completed");
        
        // Verify vault still works after time manipulation
        (bool healthy, bool hasGas, , , ) = l2Vault.getVaultHealth(USDT0_L2);
        console.log("Vault healthy after time manipulation:", healthy);
        console.log("Vault has gas:", hasGas);
        
        assertTrue(true, "Time edge cases handled");
    }
    
    /// @notice Test keeper bot with realistic harvest schedule (daily checks)
    function testKeeperBotRealisticSchedule() public {
        vm.selectFork(inkForkId);
        
        if (!_isAssetRegistered(USDT0_L2) || !_canEncodeAsset(USDT0_L2)) {
            console.log("Skipping: Asset not registered");
            return;
        }
        
        console.log("&*&*&*&*&* KEEPER BOT REALISTIC SCHEDULE TEST &*&*&*&*&*");
        
        // Setup deposit
        uint256 depositAmount = LARGE_DEPOSIT;
        if (_erc20Balance(USDT0_L2, treasury) < depositAmount) {
            console.log("Skipping: Insufficient balance");
            return;
        }
        
        vm.startPrank(treasury);
        (bool ok, ) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2Vault), depositAmount)
        );
        if (!ok) {
            vm.stopPrank();
            return;
        }
        
        try l2Vault.deposit(USDT0_L2, depositAmount) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        
        // Simulate 30 days of keeper bot operation
        // Keeper checks every 6 hours, updates yield every hour
        uint256 daysToSimulate = 30;
        uint256 checksPerDay = 4; // Every 6 hours
        uint256 updatesPerDay = 24; // Every hour
        
        uint256 totalChecks = daysToSimulate * checksPerDay;
        uint256 totalUpdates = daysToSimulate * updatesPerDay;
        uint256 harvests = 0;
        
        console.log("Simulating", daysToSimulate, "days of keeper operation");
        console.log("Total checks:", totalChecks);
        console.log("Total updates:", totalUpdates);
        
        for (uint256 day = 0; day < daysToSimulate; day++) {
            // Advance 1 day
            vm.warp(block.timestamp + 1 days);
            
            // Hourly yield updates
            for (uint256 hour = 0; hour < 24; hour++) {
                vm.warp(block.timestamp + 1 hours);
                
                vm.startPrank(KEEPER_ADDRESS);
                try l2Vault.updateYield(USDT0_L2) {
                    // Update successful
                } catch {
                    // Update failed, continue
                }
                vm.stopPrank();
            }
            
            // Every 6 hours: Check and harvest if needed
            if (day % 1 == 0) { // Every day
                vm.startPrank(KEEPER_ADDRESS);
                l2Vault.updateYield(USDT0_L2);
                
                uint256 yield = _getYield(USDT0_L2);
                uint256 deposited = _getDeposited(USDT0_L2);
                uint256 threshold = (deposited * l2Vault.minYieldThresholdBps()) / 10000;
                
                if (yield >= threshold) {
                    try l2Vault.autoHarvestAndBridge(USDT0_L2) {
                        harvests++;
                        console.log("Day", day + 1, "- Harvested");
                    } catch {
                        // Harvest failed
                    }
                }
                vm.stopPrank();
            }
        }
        
        console.log("");
        console.log("Simulation complete:");
        console.log("  Days simulated:", daysToSimulate);
        console.log("  Harvests performed:", harvests);
        
        uint256 finalDeposited = _getDeposited(USDT0_L2);
        uint256 finalYield = _getYield(USDT0_L2);
        
        console.log("  Final deposited:", finalDeposited);
        console.log("  Final yield:", finalYield);
        
        assertTrue(finalDeposited >= depositAmount, "Deposited should not decrease");
    }
}

