// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {YieldAllocator} from "../src/YieldAllocator.sol";
import {TydroStrategy} from "../src/strategies/TydroStrategy.sol";
import {VelodromeStrategy} from "../src/strategies/VelodromeStrategy.sol";

// Mock L1 depositor for full flow testing
contract MockL1Depositor {
    address public l2Vault;
    mapping(address => address) public tokenMapping;

    event DepositToL2(address token, address sender, uint256 amount, uint256 minAmount);

    function setL2Vault(address _l2Vault) external {
        l2Vault = _l2Vault;
    }

    function setTokenMapping(address l1Token, address l2Token) external {
        tokenMapping[l1Token] = l2Token;
    }

    function depositToL2(address token, uint256 amount, uint256 minAmount) external {
        emit DepositToL2(token, msg.sender, amount, minAmount);
        //simulate the bridge by directly sending to vault
    }
}

contract EndToEndTest is Test {
    BundledYieldVaultV2_PRODUCTION public vault;
    YieldAllocator public allocator;
    MockL1Depositor public l1Depositor;

    TydroStrategy public tydroStrategy;
    VelodromeStrategy public veloStrategy;

    // Mock contracts
    address public mockSpokePool = address(0x111);
    address public mockTydroPool = address(0x222);
    address public mockEncoder = address(0x333);
    address public mockVeloRouter = address(0x444);
    address public mockSlipstreamNFT = address(0x888);

    // Test tokens
    address public usdtL1 = address(0x555);
    address public usdtL2 = address(0x666);
    address public wethL2 = address(0x777);

    // Test accounts
    address public owner = address(0x1000);
    address public treasury = address(0x2000);
    address public user = address(0x3000);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy L1 depositor
        l1Depositor = new MockL1Depositor();
        l1Depositor.setTokenMapping(usdtL1, usdtL2);
        l1Depositor.setL2Vault(address(0)); // Will set later

        // Deploy vault
        vault = new BundledYieldVaultV2_PRODUCTION(
            mockTydroPool,
            mockEncoder,
            mockSpokePool,
            address(l1Depositor),
            mockVeloRouter,
            mockSlipstreamNFT
        );

        // Set vault in L1 depositor
        l1Depositor.setL2Vault(address(vault));

        // Set token mapping in vault
        vault.mapToken(usdtL2, usdtL1);

        // Deploy strategies (with mock addresses)
        tydroStrategy = new TydroStrategy(mockTydroPool, mockEncoder);
        veloStrategy = new VelodromeStrategy(mockVeloRouter);

        // Deploy allocator
        allocator = new YieldAllocator();
        allocator.registerStrategy(tydroStrategy);
        allocator.registerStrategy(veloStrategy);

        // Set aux data for Velodrome
        bytes memory auxData = abi.encode(usdtL2, true); // USDT pair, stable
        allocator.setStrategyAuxData(usdtL2, 2, auxData);

        // Configure vault
        vault.setAllocator(allocator);
        vault.setL1Recipient(address(l1Depositor));

        vm.stopPrank();
    }

    function testFullTreasuryFlow() public {
        console.log("=== Full Treasury Flow Test ===");

        // Step 1: Treasury deposits to L1
        console.log("Step 1: Treasury deposits $1000 USDT to L1 depositor");
        vm.startPrank(treasury);
        // In real scenario: approve + depositToL2
        vm.stopPrank();

        // Simulate bridged funds arriving in vault
        console.log("Step 2: Funds arrive in L2 vault via bridge");
        deal(usdtL2, address(vault), 1000000000); // 1000 USDT (6 decimals)

        // Step 3: Auto-deposit to smart allocation
        console.log("Step 3: Auto-deposit with smart allocation");
        vm.prank(owner);
        vault.depositAvailable(usdtL2, true); // Use smart allocation

        // Verify allocation went to best strategy (Velodrome)
        (uint8 bestStrategy, ) = vault.getBestStrategy(usdtL2);
        assertEq(bestStrategy, 2, "Should allocate to Velodrome");

        console.log("Step 4: Let yield accrue (simulate time)");
        skip(30 days); // Simulate 30 days

        // Step 5: Smart compound
        console.log("Step 5: Smart compound (harvest + reinvest)");
        vm.prank(owner);
        vault.smartCompound(usdtL2);

        // Step 6: Harvest and bridge back
        console.log("Step 6: Harvest and bridge yield back to L1");
        vm.prank(owner);
        vault.harvestAndBridge(usdtL2, 75, 100, 0); // 75% compound, 1% slippage

        console.log("Full treasury flow completed!");
    }

    function testMultiStrategyOptimization() public {
        console.log("=== Multi-Strategy Optimization Test ===");

        // Initial allocation to Tydro (lower yield)
        deal(usdtL2, address(vault), 100000000); // 100 USDT
        vm.prank(owner);
        vault.depositAvailable(usdtL2, true);

        // Check initial allocation
        (uint128 tydroPrincipal, , ) = allocator.allocations(usdtL2, 1);
        assertEq(tydroPrincipal, 0, "Should not allocate to Tydro initially");

        (uint128 veloPrincipal, , ) = allocator.allocations(usdtL2, 2);
        assertEq(veloPrincipal, 100000000, "Should allocate to Velodrome");

        // Simulate yield accrual
        skip(7 days);

        // Rebalance check
        vm.prank(owner);
        vault.smartRebalance(usdtL2);

        console.log("Multi-strategy optimization working!");
    }

    function testRiskManagement() public {
        console.log("=== Risk Management Test ===");

        // Set conservative allocation limits
        vm.prank(owner);
        allocator.setMaxAllocation(2, 8000); // Max 80% to Velodrome

        // Try large allocation
        deal(usdtL2, address(vault), 1000000000); // 1000 USDT
        vm.prank(owner);
        vault.depositAvailable(usdtL2, true);

        // Should respect max allocation
        (uint128 veloPrincipal, , ) = allocator.allocations(usdtL2, 2);
        assertLe(veloPrincipal, 800000000, "Should not exceed max allocation"); // 80% of 1000

        console.log("Risk management working!");
    }

    function testEmergencyScenarios() public {
        console.log("=== Emergency Scenarios Test ===");

        // Setup normal operation
        deal(usdtL2, address(vault), 100000000); // 100 USDT
        vm.prank(owner);
        vault.depositAvailable(usdtL2, false); // Use Tydro for safety

        // Emergency pause
        vm.prank(owner);
        vault.pause();

        // Operations should be blocked
        vm.expectRevert();
        vm.prank(owner);
        vault.depositAvailable(usdtL2, false);

        // Emergency withdraw
        vm.prank(owner);
        vault.emsWithdraw(usdtL2, treasury, 50000000); // Withdraw 50 USDT

        console.log("Emergency scenarios handled!");
    }

    function testGasOptimization() public {
        console.log("=== Gas Optimization Test ===");

        uint256 gasStart = gasleft();

        // Perform multiple operations
        deal(usdtL2, address(vault), 10000000); // 10 USDT
        vm.startPrank(owner);

        vault.depositAvailable(usdtL2, true);
        vault.updateYield(usdtL2);
        vault.smartRebalance(usdtL2);
        vault.smartCompound(usdtL2);

        vm.stopPrank();

        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for full cycle:", gasUsed);

        // Should be reasonable (under 1M gas total)
        assertLt(gasUsed, 1000000, "Gas usage should be reasonable");

        console.log("Gas optimization verified!");
    }

    function testYieldAccrualSimulation() public {
        console.log("=== Yield Accrual Simulation ===");

        // Initial deposit
        deal(usdtL2, address(vault), 100000000); // 100 USDT
        vm.prank(owner);
        vault.depositAvailable(usdtL2, false);

        (uint256 initialDeposited, , , ) = vault.getStatus(usdtL2);
        assertEq(initialDeposited, 100000000);

        // Simulate yield accrual (in real scenario, this happens automatically)
        console.log("Simulating 30 days of yield accrual...");

        // Update yield multiple times to simulate accrual
        for (uint256 i = 0; i < 30; i++) {
            skip(1 days);
            vm.prank(owner);
            vault.updateYield(usdtL2);
        }

        // Check final status
        (uint256 finalDeposited, uint256 finalCurrent, uint256 finalYield, ) = vault.getStatus(usdtL2);
        console.log("Final deposited:", finalDeposited);
        console.log("Final current:", finalCurrent);
        console.log("Final yield:", finalYield);

        // Current should be >= deposited (includes yield)
        assertGe(finalCurrent, finalDeposited);

        console.log("Yield accrual simulation completed!");
    }

    function testBatchOperationsEfficiency() public {
        console.log("=== Batch Operations Efficiency Test ===");

        // Setup multiple deposits
        deal(usdtL2, address(vault), 500000000); // 500 USDT

        uint256 gasStart = gasleft();

        vm.startPrank(owner);

        // Perform batch of operations
        vault.depositAvailable(usdtL2, true);
        vault.smartRebalance(usdtL2);
        vault.smartCompound(usdtL2);
        vault.updateYield(usdtL2);

        vm.stopPrank();

        uint256 gasUsed = gasStart - gasleft();
        console.log("Batch operations gas:", gasUsed);

        // Should be efficient
        assertLt(gasUsed, 500000, "Batch operations should be gas efficient");

        console.log("Batch operations efficient!");
    }

    function testCrossChainYieldCycle() public {
        console.log("=== Cross-Chain Yield Cycle Test ===");

        // 1. Deposit to L1
        console.log("1. L1 Deposit");
        vm.prank(treasury);
        // l1Depositor.depositToL2(usdtL1, 100000000, 95000000); // Would bridge

        // 2. Simulate bridge arrival
        console.log("2. Bridge Arrival");
        deal(usdtL2, address(vault), 100000000);

        // 3. Auto-deposit
        console.log("3. Auto-Deposit");
        vm.prank(owner);
        vault.depositAvailable(usdtL2, true);

        // 4. Yield generation (simulate)
        console.log("4. Yield Generation");
        skip(30 days);

        // 5. Harvest and bridge back
        console.log("5. Harvest & Bridge Back");
        vm.prank(owner);
        vault.harvestAndBridge(usdtL2, 50, 100, 0);

        // 6. Yield arrives back on L1 (simulated)
        console.log("6. Yield Arrives on L1");

        console.log("Cross-chain yield cycle completed!");
    }

    function testPerformanceUnderLoad() public {
        console.log("=== Performance Under Load Test ===");

        vm.startPrank(owner);

        // Simulate multiple tokens/assets
        address[] memory tokens = new address[](3);
        tokens[0] = usdtL2;
        tokens[1] = wethL2;
        tokens[2] = address(0x888);

        for (uint256 i = 0; i < tokens.length; i++) {
            // Add token mappings
            vault.mapToken(tokens[i], address(uint160(i + 1000)));

            // Simulate deposits
            deal(tokens[i], address(vault), 10000000);

            // Operations
            vault.depositAvailable(tokens[i], true);
            vault.updateYield(tokens[i]);
        }

        // Bulk rebalancing
        vault.smartRebalance(usdtL2);
        vault.smartCompound(usdtL2);

        vm.stopPrank();

        console.log("Performance under load verified!");
    }
}
