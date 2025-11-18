// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {BundledYieldVaultV2_RELAY} from "../src/BundledYieldVaultV2_RELAY.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockTydroPool} from "./mocks/MockTydroPool.sol";
import {MockL2Encoder} from "./mocks/MockL2Encoder.sol";
import {MockAcrossBridge, MockRelayDepository} from "./mocks/MockBridge.sol";

/// @title CrossChainIntegrationBothBridgesTest
/// @notice Integration tests for BOTH Across and Relay Protocol bridges
contract CrossChainIntegrationBothBridgesTest is Test {
    L1DepositorV2_PRODUCTION public l1Depositor;
    BundledYieldVaultV2_PRODUCTION public l2VaultAcross;
    BundledYieldVaultV2_RELAY public l2VaultRelay;
    
    MockERC20 public usdtL1;
    MockERC20 public usdt0L2;
    MockTydroPool public tydroPool;
    MockL2Encoder public l2Encoder;
    MockAcrossBridge public acrossBridge;
    MockRelayDepository public relayDepository;
    
    address public treasury = address(0x1234); // Treasury multisig
    address public constant SLIPSTREAM_POSITION_NFT = address(0x999);
    uint256 public constant L1_CHAIN_ID = 1;
    uint256 public constant INK_CHAIN_ID = 12345; // Mock Ink chain ID
    
    function setUp() public {
        // Deploy mock tokens
        usdtL1 = new MockERC20("USDT", "USDT");
        usdt0L2 = new MockERC20("USDT0", "USDT0");
        
        // Deploy mock protocols
        tydroPool = new MockTydroPool();
        l2Encoder = new MockL2Encoder();
        acrossBridge = new MockAcrossBridge();
        relayDepository = new MockRelayDepository();
        
        // Mint tokens to treasury
        usdtL1.mint(treasury, 1000000 * 1e6); // $1M USDT
        usdt0L2.mint(treasury, 1000000 * 1e6); // $1M USDT0
        
        // Configure mock encoder/pool asset IDs
        l2Encoder.setAssetId(address(usdt0L2), 2);
        tydroPool.setTokenConfig(address(usdt0L2), 2);

        // Deploy L2 vault with Across
        l2VaultAcross = new BundledYieldVaultV2_PRODUCTION(
            address(tydroPool),
            address(l2Encoder),
            address(acrossBridge),
            treasury,
            address(0x01D40099fCD87C018969B0e8D4aB1633Fb34763C), // Velodrome router
            SLIPSTREAM_POSITION_NFT
        );
        l2VaultAcross.transferOwnership(treasury);
        
        // Deploy L2 vault with Relay
        l2VaultRelay = new BundledYieldVaultV2_RELAY(
            address(tydroPool),
            address(l2Encoder),
            address(relayDepository),
            treasury
        );
        l2VaultRelay.transferOwnership(treasury);
        
        // Deploy L1 depositor (for Across)
        l1Depositor = new L1DepositorV2_PRODUCTION(
            address(acrossBridge),
            address(l2VaultAcross),
            INK_CHAIN_ID
        );
        l1Depositor.transferOwnership(treasury);
        
        // Setup token mappings
        vm.startPrank(treasury);
        l1Depositor.setTokenMapping(address(usdtL1), address(usdt0L2));
        l2VaultAcross.mapToken(address(usdt0L2), address(usdtL1));
        l2VaultAcross.setL1Recipient(address(l1Depositor));
        l2VaultRelay.setTokenMapping(address(usdt0L2), address(usdtL1));
        l2VaultRelay.setL1Recipient(address(l1Depositor));
        vm.stopPrank();
        
        // Fund both vaults with gas
        vm.deal(address(l2VaultAcross), 0.1 ether);
        vm.deal(address(l2VaultRelay), 0.1 ether);
    }
    
    /// @notice Test full flow with Across bridge
    function testFullFlowAcross() public {
        uint256 depositAmount = 10000 * 1e6; // $10k USDT
        
        // Step 1: Deposit on L1
        vm.startPrank(treasury);
        usdtL1.approve(address(l1Depositor), depositAmount);
        // Allow 1% slippage tolerance explicitly
        l1Depositor.setMaxSlippage(100);
        l1Depositor.depositToL2(address(usdtL1), depositAmount, depositAmount * 99 / 100);
        vm.stopPrank();
        
        assertEq(l1Depositor.totalDeposits(address(usdtL1)), depositAmount);
        
        // Step 2: Tokens arrive on L2 (simulate bridge fill)
        usdt0L2.mint(address(l2VaultAcross), depositAmount);
        
        // Step 3: Deposit to Tydro
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2VaultAcross), depositAmount);
        l2VaultAcross.deposit(address(usdt0L2), depositAmount);
        vm.stopPrank();
        
        (uint256 deposited,,,) = l2VaultAcross.getStatus(address(usdt0L2));
        assertEq(deposited, depositAmount);
        
        // Step 4: Simulate yield (1 week)
        vm.warp(block.timestamp + 7 days);
        // Simulate yield arriving to pool so withdraw can succeed
        usdt0L2.mint(address(tydroPool), depositAmount / 100);
        l2VaultAcross.updateYield(address(usdt0L2));
        
        uint256 yield = l2VaultAcross.getYieldAvailable(address(usdt0L2));
        assertGt(yield, 0);
        
        // Step 5: Harvest and bridge via Across
        vm.startPrank(treasury);
        l2VaultAcross.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        vm.stopPrank();
        
        console.log("Across bridge test completed!");
    }
    
    /// @notice Test full flow with Relay Protocol bridge
    function testFullFlowRelay() public {
        uint256 depositAmount = 10000 * 1e6; // $10k USDT
        
        // Directly deposit to Relay vault (simulating bridged tokens)
        usdt0L2.mint(address(l2VaultRelay), depositAmount);
        
        // Deposit to Tydro
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2VaultRelay), depositAmount);
        l2VaultRelay.deposit(address(usdt0L2), depositAmount);
        vm.stopPrank();
        
        (uint256 deposited,,,) = l2VaultRelay.getStatus(address(usdt0L2));
        assertEq(deposited, depositAmount);
        
        // Simulate yield (1 week)
        vm.warp(block.timestamp + 7 days);
        usdt0L2.mint(address(tydroPool), depositAmount / 100);
        // For relay vault (which reads token balance in this test), also mint a small amount directly
        usdt0L2.mint(address(l2VaultRelay), depositAmount / 1000);
        l2VaultRelay.updateYield(address(usdt0L2));
        
        uint256 yield = l2VaultRelay.getYieldAvailable(address(usdt0L2));
        assertGt(yield, 0);
        
        // Harvest and bridge via Relay
        vm.startPrank(treasury);
        // Approve Relay depository to pull tokens in mock
        usdt0L2.approve(address(l2VaultRelay), type(uint256).max);
        l2VaultRelay.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        vm.stopPrank();
        
        console.log("Relay bridge test completed!");
    }
    
    /// @notice Compare gas costs between bridges
    function testGasComparison() public {
        uint256 depositAmount = 10000 * 1e6;

        // Setup both vaults with identical deposits
        usdt0L2.mint(address(l2VaultAcross), depositAmount);
        usdt0L2.mint(address(l2VaultRelay), depositAmount);

        vm.startPrank(treasury);
        usdt0L2.approve(address(l2VaultAcross), depositAmount);
        l2VaultAcross.deposit(address(usdt0L2), depositAmount);
        usdt0L2.approve(address(l2VaultRelay), depositAmount);
        l2VaultRelay.deposit(address(usdt0L2), depositAmount);
        vm.stopPrank();

        // Simulate identical yield conditions
        vm.warp(block.timestamp + 7 days);
        usdt0L2.mint(address(tydroPool), depositAmount / 50);
        usdt0L2.mint(address(l2VaultAcross), depositAmount / 2000);
        usdt0L2.mint(address(l2VaultRelay), depositAmount / 2000);

        uint256 snapshot = vm.snapshot();

        vm.startPrank(treasury);
        l2VaultAcross.updateYield(address(usdt0L2));
        uint256 gasAcross = gasleft();
        l2VaultAcross.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        gasAcross = gasAcross - gasleft();
        vm.stopPrank();

        vm.revertTo(snapshot);

        vm.startPrank(treasury);
        l2VaultRelay.updateYield(address(usdt0L2));
        uint256 gasRelay = gasleft();
        usdt0L2.approve(address(l2VaultRelay), type(uint256).max);
        l2VaultRelay.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        gasRelay = gasRelay - gasleft();
        vm.stopPrank();

        console.log("Across gas:", gasAcross);
        console.log("Relay gas:", gasRelay);
        console.log("Difference:", gasAcross > gasRelay ? gasAcross - gasRelay : gasRelay - gasAcross);
    }

    /// @notice L1 Across deposit should revert if minAmount is set too low vs allowed slippage
    function testAcrossDepositSlippageGuard() public {
        uint256 amount = 1_000_000; // 1 USDT (6 decimals)
        vm.startPrank(treasury);
        usdtL1.approve(address(l1Depositor), amount);
        // Set max slippage to 0.5%
        l1Depositor.setMaxSlippage(50);
        // Expected min ≈ 995000 (amount * (1 - 0.005))
        uint256 tooHighMin = 999000; // higher than allowed => should revert
        vm.expectRevert(L1DepositorV2_PRODUCTION.SlippageTooHigh.selector);
        l1Depositor.depositToL2(address(usdtL1), amount, tooHighMin);
        // Should succeed with acceptable min
        l1Depositor.depositToL2(address(usdtL1), amount, 995000);
        vm.stopPrank();
    }

    /// @notice Vaults should respect paused state on deposit and harvest
    function testPauseGuards() public {
        uint256 amount = 10_000 * 1e6;
        usdt0L2.mint(address(l2VaultAcross), amount);
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2VaultAcross), amount);
        l2VaultAcross.pause();
        vm.expectRevert();
        l2VaultAcross.deposit(address(usdt0L2), amount);
        l2VaultAcross.unpause();
        l2VaultAcross.deposit(address(usdt0L2), amount);
        vm.warp(block.timestamp + 5 days);
        usdt0L2.mint(address(tydroPool), amount / 100);
        l2VaultAcross.updateYield(address(usdt0L2));
        l2VaultAcross.pause();
        vm.expectRevert();
        l2VaultAcross.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        l2VaultAcross.unpause();
        l2VaultAcross.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        vm.stopPrank();
    }

    /// @notice Relay vault: minBridgeAmount higher than expected after fee should revert
    function testRelayMinBridgeAmountTooHigh() public {
        uint256 depositAmount = 20_000 * 1e6;
        usdt0L2.mint(address(l2VaultRelay), depositAmount);
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2VaultRelay), depositAmount);
        l2VaultRelay.deposit(address(usdt0L2), depositAmount);
        vm.warp(block.timestamp + 3 days);
        usdt0L2.mint(address(tydroPool), depositAmount / 100);
        l2VaultRelay.updateYield(address(usdt0L2));
        // Set fee to 1% and demand a min that exceeds post-fee amount
        l2VaultRelay.setMaxBridgeFee(100);
        // Force approval for internal transfer if needed
        usdt0L2.approve(address(l2VaultRelay), type(uint256).max);
        // Compute an obviously too-high min: equal to the pre-fee amount
        vm.expectRevert();
        l2VaultRelay.harvestAndBridge(address(usdt0L2), 0, 100, type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Only owner can call critical functions
    function testOnlyOwnerGuards() public {
        uint256 amount = 1_000 * 1e6;
        address attacker = address(0xBEEF);
        vm.startPrank(attacker);
        vm.expectRevert();
        l2VaultAcross.deposit(address(usdt0L2), amount);
        vm.expectRevert();
        l2VaultAcross.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        vm.expectRevert();
        l1Depositor.depositToL2(address(usdtL1), amount, amount);
        vm.stopPrank();
    }

    /// @notice Revert when using unmapped tokens
    function testUnmappedTokenReverts() public {
        MockERC20 random = new MockERC20("RND", "RND");
        random.mint(treasury, 1e24);
        vm.startPrank(treasury);
        random.approve(address(l2VaultAcross), type(uint256).max);
        vm.expectRevert();
        l2VaultAcross.deposit(address(random), 1000);
        vm.stopPrank();
    }
}

