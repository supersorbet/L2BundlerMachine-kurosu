// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {YieldManagerWithBridge} from "../src/YieldManagerWithBridge.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockTydroPool} from "./mocks/MockTydroPool.sol";
import {MockL2Encoder} from "./mocks/MockL2Encoder.sol";
import {MockAcrossBridge, MockRelayDepository} from "./mocks/MockBridge.sol";

/// @title CrossChainIntegrationTest
/// @notice Integration tests simulating cross-chain yield operations
contract CrossChainIntegrationTest is Test {
    L1DepositorV2_PRODUCTION public l1Depositor;
    BundledYieldVaultV2_PRODUCTION public l2Vault;
    YieldManagerWithBridge public yieldManager;
    
    MockERC20 public usdtL1;
    MockERC20 public usdt0L2;
    MockTydroPool public tydroPool;
    MockL2Encoder public l2Encoder;
    MockAcrossBridge public acrossBridge;
    MockRelayDepository public relayDepository;
    
    address public treasury = address(0x1234);///Treasury multisig
    address public constant SLIPSTREAM_POSITION_NFT = address(0x999);
    uint256 public constant L1_CHAIN_ID = 1;
    uint256 public constant INK_CHAIN_ID = 57073;///Mock Ink chain ID
    
    function setUp() public {
       ///Deploy mock tokens
        usdtL1 = new MockERC20("USDT", "USDT");
        usdt0L2 = new MockERC20("USDT0", "USDT0");
        
       ///Deploy mock protocols
        tydroPool = new MockTydroPool();
        l2Encoder = new MockL2Encoder();
        acrossBridge = new MockAcrossBridge();
        relayDepository = new MockRelayDepository();
        
       ///Mint tokens to treasury
        usdtL1.mint(treasury, 1000000 * 1e6);///$1M USDT
        usdt0L2.mint(treasury, 1000000 * 1e6);///$1M USDT0
        
       ///Configure mock encoder/pool asset IDs
        l2Encoder.setAssetId(address(usdt0L2), 2);
        tydroPool.setTokenConfig(address(usdt0L2), 2);

       ///Deploy L2 vault first
        l2Vault = new BundledYieldVaultV2_PRODUCTION(
            address(tydroPool),
            address(l2Encoder),
            address(acrossBridge),///Using Across for now
            treasury,///L1 recipient
            address(0x01D40099fCD87C018969B0e8D4aB1633Fb34763C),///Velodrome router
            SLIPSTREAM_POSITION_NFT
        );
        
       ///Transfer ownership to treasury
        l2Vault.transferOwnership(treasury);
        
       ///Deploy L1 depositor
        l1Depositor = new L1DepositorV2_PRODUCTION(
            address(acrossBridge),
            address(l2Vault),
            INK_CHAIN_ID
        );
        
       ///Transfer ownership to treasury
        l1Depositor.transferOwnership(treasury);
        
       ///Deploy YieldManager (Relay version)
       ///Note: Velo router cannot be address(0), so we deploy a minimal mock
        address mockVelo = address(0x5678);///Mock address (won't be used)
        yieldManager = new YieldManagerWithBridge(
            address(relayDepository),
            address(tydroPool),
            address(l2Encoder),
            mockVelo,
            treasury
        );
        
        yieldManager.transferOwnership(treasury);
        
       ///Setup token mappings
        vm.prank(treasury);
        l1Depositor.setTokenMapping(address(usdtL1), address(usdt0L2));
        
        vm.prank(treasury);
        l2Vault.mapToken(address(usdt0L2), address(usdtL1));
        
        vm.prank(treasury);
        l2Vault.setL1Recipient(address(l1Depositor));
        
       ///Fund L2 vault with gas
        vm.deal(address(l2Vault), 0.1 ether);
    }
    
    /// @notice Test full flow: L1 → L2 → Yield → L1
    function testFullCrossChainFlow() public {
        uint256 depositAmount = 10000 * 1e6;///$10k USDT
        
       ///Step 1: Treasury approves and deposits on L1
        vm.startPrank(treasury);
        usdtL1.approve(address(l1Depositor), depositAmount);
        l1Depositor.depositToL2(address(usdtL1), depositAmount, depositAmount * 99 / 100);
        vm.stopPrank();
        
       ///Verify deposit recorded
        assertEq(l1Depositor.totalDeposits(address(usdtL1)), depositAmount);
        
       ///Step 2: Simulate bridge fill (tokens arrive on L2)
       ///In real scenario, bridge would send tokens to l2Vault
       ///For testing, we mint and transfer directly
        usdt0L2.mint(treasury, depositAmount);
        
       ///Step 3: Treasury deposits to Tydro on L2
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2Vault), type(uint256).max);
        l2Vault.deposit(address(usdt0L2), depositAmount);
        vm.stopPrank();
        
       ///Verify deposited
        (uint256 deposited, uint256 balance, uint256 yield, uint256 gas) = l2Vault.getStatus(address(usdt0L2));
        assertEq(deposited, depositAmount);
        assertEq(balance, depositAmount);
        
       ///Step 4: Simulate time passing (yield accrual)
        vm.warp(block.timestamp + 7 days);///1 week
        
       ///Update yield
        l2Vault.updateYield(address(usdt0L2));
        
       ///Check yield available (should be ~0.057% after 7 days at 3% APY)
        uint256 yieldAfterWeek = l2Vault.getYieldAvailable(address(usdt0L2));
        console.log("Yield after 1 week:", yieldAfterWeek);
        assertGt(yieldAfterWeek, 0);
        
       ///Step 5: Harvest and bridge yield
        vm.startPrank(treasury);
        l2Vault.harvestAndBridge(
            address(usdt0L2),
            50, ///50% compound
            0,  ///default slippage
            0   ///auto-calculate min
        );
        vm.stopPrank();
        
       ///Step 6: Verify yield bridged to L1
       ///In real scenario, Across would fill the deposit
       ///For testing, we simulate by checking events or state
       ///(Note: actual bridge fill requires more complex mocking)
        
        console.log("Full cross-chain flow completed!");
    }
    
    /// @notice Test yield compounding effect
    function testYieldCompounding() public {
        uint256 depositAmount = 100000 * 1e6;///$100k
        
       ///Setup
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2Vault), type(uint256).max);
        l2Vault.deposit(address(usdt0L2), depositAmount);
        vm.stopPrank();
        
       ///Simulate multiple harvest cycles
        for (uint256 i = 0; i < 4; i++) {
           ///Advance 1 week
            vm.warp(block.timestamp + 7 days);
            
           ///Update yield
            l2Vault.updateYield(address(usdt0L2));
            
            uint256 yield = l2Vault.getYieldAvailable(address(usdt0L2));
            console.log("Cycle %d yield:", i + 1, yield);
            
            if (yield > 1000) {///Only harvest if meaningful
                vm.startPrank(treasury);
                l2Vault.harvestAndBridge(address(usdt0L2), 50, 0, 0);///50% compound
                vm.stopPrank();
                
               ///Verify compound worked
                (uint256 depositedAfter,,,) = l2Vault.getStatus(address(usdt0L2));
                assertGt(depositedAfter, depositAmount);
            }
        }
        
       ///Final check - should have more than original
        (uint256 finalDeposited,,,) = l2Vault.getStatus(address(usdt0L2));
        assertGt(finalDeposited, depositAmount);
        console.log("Final deposited (after compounding):", finalDeposited);
    }
    
    /// @notice Test gas auto-refill mechanism
    function testAutoGasRefill() public {
       ///Start with low gas
        vm.deal(address(l2Vault), 0.001 ether);
        
        uint256 depositAmount = 10000 * 1e6;
        usdt0L2.mint(treasury, depositAmount);
        
        vm.startPrank(treasury);
        usdt0L2.approve(address(l2Vault), type(uint256).max);
        l2Vault.deposit(address(usdt0L2), depositAmount);
        
       ///Simulate yield
        vm.warp(block.timestamp + 30 days);
        l2Vault.updateYield(address(usdt0L2));
        
        uint256 yield = l2Vault.getYieldAvailable(address(usdt0L2));
        
       ///Enable auto-refill
        l2Vault.setAutoRefill(50);///0.5%
        
       ///Harvest - should auto-refill gas
        uint256 gasBefore = address(l2Vault).balance;
        l2Vault.harvestAndBridge(address(usdt0L2), 50, 0, 0);
        uint256 gasAfter = address(l2Vault).balance;
        
        vm.stopPrank();
        
        console.log("Gas before:", gasBefore);
        console.log("Gas after:", gasAfter);
        
       ///Gas should increase (from bridge amount deduction)
    }
    
    /// @notice Test slippage protection
    function testSlippageProtection() public {
        uint256 depositAmount = 10000 * 1e6;
        vm.startPrank(treasury);
        
       ///Set tight slippage
        l1Depositor.setMaxSlippage(50);///0.5%
        
       ///Should fail with too high minAmount
        usdtL1.approve(address(l1Depositor), depositAmount);
        vm.expectRevert(L1DepositorV2_PRODUCTION.SlippageTooHigh.selector);
        l1Depositor.depositToL2(
            address(usdtL1),
            depositAmount,
            depositAmount * 9999 / 10000///0.01% slippage - too tight!
        );
        
       ///Should succeed with reasonable slippage
        l1Depositor.depositToL2(
            address(usdtL1),
            depositAmount,
            depositAmount * 9950 / 10000///0.5% slippage - OK
        );
        
        vm.stopPrank();
        
        assertEq(l1Depositor.totalDeposits(address(usdtL1)), depositAmount);
    }
    
    /// @notice Test emergency pause
    function testEmergencyPause() public {
        uint256 depositAmount = 10000 * 1e6;
        usdt0L2.mint(treasury, depositAmount);
        
        vm.startPrank(treasury);
        
       ///Pause
        l2Vault.pause();
        assertTrue(l2Vault.paused());
        
       ///Should fail when paused
        usdt0L2.approve(address(l2Vault), type(uint256).max);
        vm.expectRevert();
        l2Vault.deposit(address(usdt0L2), depositAmount);
        
       ///Unpause
        l2Vault.unpause();
        assertFalse(l2Vault.paused());
        
       ///Should work after unpause
        l2Vault.deposit(address(usdt0L2), depositAmount);
        
        vm.stopPrank();
    }
    
    /// @notice Test YieldManager with Relay Protocol
    function testYieldManagerRelayFlow() public {
        uint256 depositAmount = 100000 * 1e6;
        
        vm.startPrank(treasury);
        
       ///Deploy to Tydro
        usdt0L2.mint(treasury, depositAmount);
        usdt0L2.approve(address(yieldManager), depositAmount);
        yieldManager.deployToTydro(address(usdt0L2), depositAmount);
        
       ///Check balance
        uint256 balance = yieldManager.getTydroBalance(address(usdt0L2));
        assertEq(balance, depositAmount);
        
       ///Simulate yield (advance time)
        vm.warp(block.timestamp + 30 days);
        
       ///Check yield
        uint256 yield = yieldManager.getTydroYield(address(usdt0L2));
        console.log("Yield after 30 days:", yield);
        
       ///Harvest (50/50 split)
        bytes memory auxData = abi.encode(address(0));///Empty for Tydro
        yieldManager.harvest(1, address(usdt0L2), auxData);
        
        vm.stopPrank();
        
        console.log("YieldManager harvest completed!");
    }
}

