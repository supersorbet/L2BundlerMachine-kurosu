// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BundledYieldVaultV2__MULTICALL} from "../src/BundledYieldVaultV2_PRODUCTION_MULTICALL.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IL2Pool} from "../src/interfaces/IL2Pool.sol";
import {IL2Encoder} from "../src/interfaces/IL2Encoder.sol";
import {ISlipstreamHelper} from "../src/interfaces/ISlipstreamHelper.sol";

/// @title MulticallForkTests
/// @notice Comprehensive fork tests for multicall functionality with Slipstream operations
/// @dev Tests multicall patterns, gas optimization, and Slipstream LP operations
/// @dev Run with: INK_RPC=<url> forge test --match-contract MulticallForkTests -vvvv
/// @dev Or use: ./test_multicall_fork.sh
contract MulticallForkTests is Test {
    // Ink L2 addresses (Chain ID: 57073)
    address public constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4;
    address public constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    address public constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c;
    address public constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;
    address public constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address public constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    address public constant WETH_L2 = 0x4200000000000000000000000000000000000006; // WETH on Ink
    
    address public treasury;
    uint256 public inkForkId;
    
    BundledYieldVaultV2__MULTICALL public vault;
    
    // Test amounts
    uint256 public constant TEST_DEPOSIT = 1000 * 1e6; // $1000 USDT0 (6 decimals)
    uint256 public constant TEST_ZAP_AMOUNT = 100 * 1e6; // $100 USDT0 for zapping
    
    function setUp() public {
        // Create Ink fork
        string memory inkRpc = vm.envString("INK_RPC");
        if (bytes(inkRpc).length == 0) {
            inkRpc = "https://rpc-gel.inkonchain.com";
        }
        inkForkId = vm.createFork(inkRpc);
        vm.selectFork(inkForkId);
        
        // Set treasury from env or use default
        try vm.envAddress("TREASURY_ADDRESS") returns (address _treasury) {
            treasury = _treasury;
        } catch {
            treasury = address(this); // Use test contract as treasury
        }
        
        // Deploy MULTICALL vault on Ink fork
        vm.selectFork(inkForkId);
        vault = new BundledYieldVaultV2__MULTICALL(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            treasury,
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
        );
        
        // Setup ownership
        vault.transferOwnership(treasury);
        
        // Setup token mappings
        vm.startPrank(treasury);
        vault.mapToken(USDT0_L2, 0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT L1
        if (WETH_L2 != address(0)) {
            vault.mapToken(WETH_L2, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH L1
        }
        vault.setL1Recipient(treasury); // For testing, use treasury as recipient
        vm.stopPrank();
        
        // Fund treasury with tokens and ETH
        deal(USDT0_L2, treasury, 10000 * 1e6); // $10k USDT0
        deal(address(vault), 0.1 ether); // Gas for vault
        deal(treasury, 1 ether); // Gas for treasury
        
        console.log("=== Multicall Fork Test Setup ===");
        console.log("Vault:", address(vault));
        console.log("Treasury:", treasury);
        console.log("USDT0 Balance:", IERC20(USDT0_L2).balanceOf(treasury));
        console.log("");
    }
    
    /// @notice Test 1: Basic multicall - Update yield and check status
    function testBasicMulticall() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit some tokens first
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Build multicall array
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            vault.updateYield.selector,
            USDT0_L2
        );
        calls[1] = abi.encodeWithSelector(
            vault.getStatus.selector,
            USDT0_L2
        );
        
        // Execute multicall
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Decode results
        (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, uint256 gasBalance) = 
            abi.decode(results[1], (uint256, uint256, uint256, uint256));
        
        console.log("=== Test 1: Basic Multicall ===");
        console.log("Gas Used:", gasUsed);
        console.log("Deposited:", depositedAmount);
        console.log("Current Balance:", currentBalance);
        console.log("Yield Available:", yieldAvailable);
        console.log("");
        
        assertTrue(depositedAmount > 0, "Should have deposited amount");
        vm.stopPrank();
    }
    
    /// @notice Test 2: Multicall with harvest and bridge
    function testMulticallHarvestAndBridge() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit tokens
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Fast forward time to accumulate yield (simulate)
        vm.warp(block.timestamp + 30 days);
        
        // Build multicall: Update yield → Harvest → Get status
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(
            vault.updateYield.selector,
            USDT0_L2
        );
        calls[1] = abi.encodeWithSelector(
            vault.harvestAndBridge.selector,
            USDT0_L2,
            50,  // compoundPercent
            0,   // customSlippageBps
            0    // minBridgeAmount
        );
        calls[2] = abi.encodeWithSelector(
            vault.getStatus.selector,
            USDT0_L2
        );
        
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        (uint256 depositedAmount, uint256 currentBalance, , ) = 
            abi.decode(results[2], (uint256, uint256, uint256, uint256));
        
        console.log("=== Test 2: Multicall Harvest and Bridge ===");
        console.log("Gas Used:", gasUsed);
        console.log("Deposited:", depositedAmount);
        console.log("Current Balance:", currentBalance);
        console.log("");
        
        vm.stopPrank();
    }
    
    /// @notice Test 3: Batch update yield for multiple tokens
    function testBatchUpdateYield() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit to multiple tokens (if we have them)
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Build multicall with batch update
        bytes[] memory calls = new bytes[](1);
        address[] memory tokens = new address[](1);
        tokens[0] = USDT0_L2;
        
        calls[0] = abi.encodeWithSelector(
            vault.batchUpdateYield.selector,
            tokens
        );
        
        uint256 gasBefore = gasleft();
        vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("=== Test 3: Batch Update Yield ===");
        console.log("Gas Used:", gasUsed);
        console.log("");
        
        vm.stopPrank();
    }
    
    /// @notice Test 4: Slipstream zap into position with multicall
    function testSlipstreamZapMulticall() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // First deposit some tokens
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Build multicall: Update yield → Zap into Slipstream → Get status
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            vault.updateYield.selector,
            USDT0_L2
        );
        
        // Zap into Slipstream position
        calls[1] = abi.encodeWithSelector(
            vault.zapIntoSlipstreamPosition.selector,
            USDT0_L2,
            WETH_L2,
            TEST_ZAP_AMOUNT,
            100,      // fee (0.01%)
            -887220,  // tickLower (full range)
            887220,   // tickUpper (full range)
            0,        // minAmount0
            0,        // minAmount1
            true      // stakeInGauge
        );
        
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        uint256 tokenId = abi.decode(results[1], (uint256));
        
        console.log("=== Test 4: Slipstream Zap Multicall ===");
        console.log("Gas Used:", gasUsed);
        console.log("Position NFT Token ID:", tokenId);
        console.log("");
        
        assertTrue(tokenId > 0, "Should have created position");
        vm.stopPrank();
    }
    
    /// @notice Test 5: Collect fees and harvest rewards (combined operation)
    function testCollectFeesAndHarvestRewards() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // First create a position
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Zap into Slipstream position
        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            WETH_L2,
            TEST_ZAP_AMOUNT,
            100,
            -887220,
            887220,
            0,
            0,
            true
        );
        
        // Fast forward time to accumulate fees
        vm.warp(block.timestamp + 7 days);
        
        // Use combined function via multicall
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(
            vault.collectFeesAndHarvestRewards.selector,
            tokenId,
            USDT0_L2,
            WETH_L2,
            100  // fee
        );
        
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        (uint256 fee0, uint256 fee1, uint256 rewards) = 
            abi.decode(results[0], (uint256, uint256, uint256));
        
        console.log("=== Test 5: Collect Fees and Harvest Rewards ===");
        console.log("Gas Used:", gasUsed);
        console.log("Fee0 Collected:", fee0);
        console.log("Fee1 Collected:", fee1);
        console.log("Rewards Harvested:", rewards);
        console.log("");
        
        vm.stopPrank();
    }
    
    /// @notice Test 6: Full yield cycle with multicall
    function testFullYieldCycleMulticall() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit tokens
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Fast forward for yield
        vm.warp(block.timestamp + 30 days);
        
        // Build full cycle multicall
        BundledYieldVaultV2__MULTICALL.ZapSlipstreamParams memory zapParams = 
            BundledYieldVaultV2__MULTICALL.ZapSlipstreamParams({
                tokenOut: WETH_L2,
                fee: 100,
                tickLower: -887220,
                tickUpper: 887220,
                minAmount0: 0,
                minAmount1: 0,
                stakeInGauge: true
            });
        
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(
            vault.fullYieldCycleZapIntoSlipstream.selector,
            USDT0_L2,
            50,  // compoundPercent
            TEST_ZAP_AMOUNT,
            zapParams
        );
        
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        uint256 tokenId = abi.decode(results[0], (uint256));
        
        console.log("=== Test 6: Full Yield Cycle Multicall ===");
        console.log("Gas Used:", gasUsed);
        console.log("Position NFT Token ID:", tokenId);
        console.log("");
        
        assertTrue(tokenId > 0, "Should have created position");
        vm.stopPrank();
    }
    
    /// @notice Test 7: Gas comparison - Separate calls vs Multicall
    function testGasComparison() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit tokens
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Test 1: Separate calls
        uint256 gasSeparate = 0;
        uint256 gasBefore = gasleft();
        vault.updateYield(USDT0_L2);
        gasSeparate += gasBefore - gasleft();
        
        gasBefore = gasleft();
        vault.getStatus(USDT0_L2);
        gasSeparate += gasBefore - gasleft();
        
        // Test 2: Multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(vault.updateYield.selector, USDT0_L2);
        calls[1] = abi.encodeWithSelector(vault.getStatus.selector, USDT0_L2);
        
        gasBefore = gasleft();
        vault.multicall(calls);
        uint256 gasMulticall = gasBefore - gasleft();
        
        console.log("=== Test 7: Gas Comparison ===");
        console.log("Separate Calls Gas:", gasSeparate);
        console.log("Multicall Gas:", gasMulticall);
        console.log("Gas Saved:", gasSeparate > gasMulticall ? gasSeparate - gasMulticall : 0);
        console.log("Savings %:", gasSeparate > gasMulticall ? 
            ((gasSeparate - gasMulticall) * 100) / gasSeparate : 0);
        console.log("");
        
        vm.stopPrank();
    }
    
    /// @notice Test 8: Batch collect fees from multiple positions
    function testBatchCollectFees() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Create multiple positions
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT * 3);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        uint256 tokenId1 = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            WETH_L2,
            TEST_ZAP_AMOUNT,
            100,
            -887220,
            887220,
            0,
            0,
            true
        );
        
        uint256 tokenId2 = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            WETH_L2,
            TEST_ZAP_AMOUNT,
            100,
            -887220,
            887220,
            0,
            0,
            true
        );
        
        // Fast forward for fees
        vm.warp(block.timestamp + 7 days);
        
        // Batch collect fees
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256 gasBefore = gasleft();
        vault.batchCollectSlipstreamFees(tokenIds);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("=== Test 8: Batch Collect Fees ===");
        console.log("Gas Used:", gasUsed);
        console.log("Positions:", tokenIds.length);
        console.log("");
        
        vm.stopPrank();
    }
    
    /// @notice Test 9: Multicall with options (continue on failure)
    function testMulticallWithOptions() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Build calls - one will fail (invalid token)
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            vault.updateYield.selector,
            USDT0_L2
        );
        calls[1] = abi.encodeWithSelector(
            vault.updateYield.selector,
            address(0xDEAD)  // Invalid token - will fail
        );
        
        // Test with requireSuccess=false (should continue)
        (bytes[] memory results, bool[] memory successes) = 
            vault.multicallWithOptions(calls, false);
        
        console.log("=== Test 9: Multicall With Options ===");
        console.log("Call 1 Success:", successes[0]);
        console.log("Call 2 Success:", successes[1]);
        console.log("");
        
        assertTrue(successes[0], "First call should succeed");
        assertFalse(successes[1], "Second call should fail");
        
        vm.stopPrank();
    }
    
    /// @notice Test 10: Complex workflow - Multiple operations in one multicall
    function testComplexWorkflowMulticall() public {
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        
        // Deposit tokens
        IERC20(USDT0_L2).approve(address(vault), TEST_DEPOSIT);
        vault.deposit(USDT0_L2, TEST_DEPOSIT);
        
        // Build complex multicall workflow
        bytes[] memory calls = new bytes[](4);
        
        // Step 1: Update yield
        calls[0] = abi.encodeWithSelector(
            vault.updateYield.selector,
            USDT0_L2
        );
        
        // Step 2: Deposit available (if any)
        calls[1] = abi.encodeWithSelector(
            vault.depositAvailable.selector,
            USDT0_L2,
            false
        );
        
        // Step 3: Get status
        calls[2] = abi.encodeWithSelector(
            vault.getStatus.selector,
            USDT0_L2
        );
        
        // Step 4: Get yield available
        calls[3] = abi.encodeWithSelector(
            vault.getYieldAvailable.selector,
            USDT0_L2
        );
        
        uint256 gasBefore = gasleft();
        bytes[] memory results = vault.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();
        
        (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, ) = 
            abi.decode(results[2], (uint256, uint256, uint256, uint256));
        
        uint256 yield = abi.decode(results[3], (uint256));
        
        console.log("=== Test 10: Complex Workflow Multicall ===");
        console.log("Gas Used:", gasUsed);
        console.log("Deposited:", depositedAmount);
        console.log("Current Balance:", currentBalance);
        console.log("Yield Available (status):", yieldAvailable);
        console.log("Yield Available (direct):", yield);
        console.log("");
        
        vm.stopPrank();
    }
}

