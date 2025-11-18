// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {YieldAllocator} from "../src/YieldAllocator.sol";
import {TydroStrategy} from "../src/strategies/TydroStrategy.sol";
import {VelodromeStrategy} from "../src/strategies/VelodromeStrategy.sol";

// Mock contracts for vault testing
contract MockSpokePool {
    event Deposit(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        uint32 quoteTimestamp,
        bytes message
    );

    function deposit(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) external payable {
        emit Deposit(
            depositor, recipient, inputToken, outputToken,
            inputAmount, outputAmount, destinationChainId, quoteTimestamp, message
        );
    }
}

contract MockTydroPool {
    mapping(address => address) public aTokens;

    constructor() {
        aTokens[address(0x123)] = address(0x456);
    }

    function getReserveData(address asset) external view returns (
        uint256, uint128, uint128, uint128, uint128, uint128, uint40, uint16, address, address, address, address, uint128, uint128, uint128
    ) {
        address aToken = aTokens[asset];
        return (
            0, 1000000000000000000, 50000000000000000, 0, 0, 0, 0, 0,
            aToken, address(0), address(0), address(0), 0, 0, 0
        );
    }

    function supply(bytes32) external {}
    function withdraw(bytes32) external returns (uint256) { return 1000000; }
}

contract MockL2Encoder {
    function encodeSupplyParams(address, uint256, uint16) external pure returns (bytes32) {
        return keccak256("supply");
    }
    function encodeWithdrawParams(address, uint256) external pure returns (bytes32) {
        return keccak256("withdraw");
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract VaultIntegrationTest is Test {
    BundledYieldVaultV2_PRODUCTION public vault;
    YieldAllocator public allocator;
    TydroStrategy public tydroStrategy;
    VelodromeStrategy public veloStrategy;

    MockSpokePool public mockSpokePool;
    MockTydroPool public mockTydroPool;
    MockL2Encoder public mockEncoder;
    MockERC20 public mockToken;

    address public owner = address(0x123);
    address public user = address(0x456);
    address public l1Recipient = address(0x789);
    address public slipstreamNFT = address(0xABC);

    address public testToken = address(0x111);
    address public l1Token = address(0x222);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mocks
        mockSpokePool = new MockSpokePool();
        mockTydroPool = new MockTydroPool();
        mockEncoder = new MockL2Encoder();
        mockToken = new MockERC20();

        // Deploy vault
        vault = new BundledYieldVaultV2_PRODUCTION(
            address(mockTydroPool),
            address(mockEncoder),
            address(mockSpokePool),
            l1Recipient,
            address(0x01D40099fCD87C018969B0e8D4aB1633Fb34763C), // Mock velo router
            slipstreamNFT
        );

        // Deploy strategies and allocator
        tydroStrategy = new TydroStrategy(address(mockTydroPool), address(mockEncoder));
        veloStrategy = new VelodromeStrategy(address(0x01D40099fCD87C018969B0e8D4aB1633Fb34763C)); // Mock velo router
        allocator = new YieldAllocator();

        // Register strategies
        allocator.registerStrategy(tydroStrategy);
        allocator.registerStrategy(veloStrategy);

        // Set token mapping
        vault.mapToken(testToken, l1Token);

        // Set up user with tokens
        // mockToken.balanceOf[user] = 1000000000; // 1000 tokens

        vm.stopPrank();
    }

    function testVaultInitialization() public {
        assertEq(vault.owner(), owner);
        assertEq(vault.l1Recipient(), l1Recipient);
        assertEq(address(vault.TYDRO_POOL()), address(mockTydroPool));
        assertEq(address(vault.ACROSS_SPOKE_POOL()), address(mockSpokePool));
    }

    function testTokenMapping() public {
        vm.prank(owner);
        vault.mapToken(testToken, l1Token);

        assertEq(vault.tokenMapping(testToken), l1Token);
    }

    function testDepositToVault() public {
        vm.startPrank(user);
        mockToken.approve(address(vault), 1000000);

        vault.deposit(testToken, 1000000);

        // Check vault status
        (uint256 deposited, uint256 current, uint256 yield, uint256 gas) = vault.getStatus(testToken);
        assertEq(deposited, 1000000);
        assertEq(current, 1000000);

        vm.stopPrank();
    }

    function testAutoDepositAvailable() public {
        // Simulate funds arriving in vault
        // mockToken.balanceOf[address(vault)] = 1000000;

        vm.prank(owner);
        vault.depositAvailable(testToken, false); // Use Tydro

        // Check status - should show deposited to Tydro
        (uint256 deposited, uint256 current, uint256 yield, uint256 gas) = vault.getStatus(testToken);
        assertEq(deposited, 1000000);
    }

    function testYieldUpdate() public {
        // Deposit first
        vm.startPrank(user);
        mockToken.approve(address(vault), 1000000);
        vault.deposit(testToken, 1000000);
        vm.stopPrank();

        // Update yield
        vm.prank(owner);
        vault.updateYield(testToken);

        // Should complete without error
        assertTrue(true);
    }

    function testHarvestAndBridge() public {
        // Deposit first
        vm.startPrank(user);
        mockToken.approve(address(vault), 1000000);
        vault.deposit(testToken, 1000000);
        vm.stopPrank();

        // Try to harvest (should fail - no yield)
        vm.prank(owner);
        vm.expectRevert(); // InsufficientYield
        vault.harvestAndBridge(testToken, 50, 0, 0);
    }

    function testDepositAndHarvest() public {
        // Deposit first
        vm.startPrank(user);
        mockToken.approve(address(vault), 1000000);
        vault.deposit(testToken, 1000000);
        vm.stopPrank();

        // Deposit and harvest (should work even with no yield)
        vm.prank(owner);
        vault.depositAndHarvest(testToken, 50, 0, 0);

        // Should complete
        assertTrue(true);
    }

    function testYieldAllocatorIntegration() public {
        vm.prank(owner);
        vault.setAllocator(allocator);

        assertEq(address(vault.yieldAllocator()), address(allocator));
    }

    function testSmartRebalance() public {
        vm.prank(owner);
        vault.setAllocator(allocator);

        vm.prank(owner);
        vault.smartRebalance(testToken);

        // Should complete without error
        assertTrue(true);
    }

    function testSmartCompound() public {
        vm.prank(owner);
        vault.setAllocator(allocator);

        vm.prank(owner);
        vault.smartCompound(testToken);

        // Should complete without error
        assertTrue(true);
    }

    function testGetBestStrategy() public {
        vm.prank(owner);
        vault.setAllocator(allocator);

        (uint8 strategyId, uint256 apy) = vault.getBestStrategy(testToken);

        // Should return Velodrome (higher APY)
        assertEq(strategyId, 2);
        assertGt(apy, 1000);
    }

    function testPauseFunctionality() public {
        // Should start unpaused
        assertFalse(vault.paused());

        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());

        vm.prank(owner);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function testPauseBlocksOperations() public {
        vm.prank(owner);
        vault.pause();

        // Try auto-deposit (should fail)
        vm.expectRevert();
        vault.depositAvailable(testToken, false);

        // Try deposit (should fail)
        vm.startPrank(user);
        mockToken.approve(address(vault), 1000000);
        vm.expectRevert();
        vault.deposit(testToken, 1000000);
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Put some ETH in vault
        vm.deal(address(vault), 1 ether);

        vm.prank(owner);
        vault.emsWithdraw(address(0), user, 0.5 ether);

        assertEq(user.balance, 0.5 ether);
    }

    function testTokenNotSupported() public {
        vm.expectRevert(); // TokenNotSupported
        vault.deposit(address(0x999), 1000000);
    }

    function testL1RecipientNotSet() public {
        vm.prank(owner);
        vault.setL1Recipient(address(0));

        vm.expectRevert(); // L1RecipientNotSet
        vm.prank(owner);
        vault.harvestAndBridge(testToken, 50, 0, 0);
    }

    function testInvalidCompoundPercent() public {
        vm.expectRevert(); // InvalidCompoundPercent
        vm.prank(owner);
        vault.harvestAndBridge(testToken, 101, 0, 0);
    }

    function testMinGasBalance() public {
        vm.prank(owner);
        vault.setMinGasBal(2 ether);

        // Should require more gas now
        assertEq(vault.minGasBalance(), 2 ether);
    }

    function testSlippageSettings() public {
        vm.prank(owner);
        vault.setDefaultSlippage(200); // 2%

        assertEq(vault.defaultSlippageBps(), 200);
    }

    function testGasRefillSettings() public {
        vm.prank(owner);
        vault.setAutoRefill(100); // 1%

        assertEq(vault.autoGasRefillBps(), 100);
    }

    function testReceiveFunction() public payable {
        // Send ETH to vault
        (bool success,) = address(vault).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(vault).balance, 1 ether);
    }

    function testRefillGas() public {
        vm.prank(owner);
        vault.refillGas{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);
    }

    function testOnlyOwnerFunctions() public {
        vm.startPrank(user);

        // Should all revert
        vm.expectRevert();
        vault.mapToken(testToken, l1Token);

        vm.expectRevert();
        vault.setL1Recipient(l1Recipient);

        vm.expectRevert();
        vault.setAllocator(allocator);

        vm.expectRevert();
        vault.pause();

        vm.expectRevert();
        vault.unpause();

        vm.expectRevert();
        vault.emsWithdraw(address(0), user, 1 ether);

        vm.stopPrank();
    }

    function testBatchOperations() public {
        // Test multiple operations in sequence
        vm.startPrank(user);
        mockToken.approve(address(vault), 10000000);

        // Multiple deposits
        vault.deposit(testToken, 1000000);
        vault.deposit(testToken, 1000000);

        vm.stopPrank();

        // Check accumulated deposits
        (uint256 deposited, , , ) = vault.getStatus(testToken);
        assertEq(deposited, 2000000);
    }
}
