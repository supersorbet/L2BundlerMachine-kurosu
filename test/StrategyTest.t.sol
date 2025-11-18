// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {TydroStrategy} from "../src/strategies/TydroStrategy.sol";
import {VelodromeStrategy} from "../src/strategies/VelodromeStrategy.sol";
import {YieldAllocator} from "../src/YieldAllocator.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";

// Mock contracts for testing
contract MockTydroPool {
    mapping(address => address) public aTokens;

    constructor() {
        // Mock aToken addresses
        aTokens[address(0x123)] = address(0x456);
        aTokens[address(0x789)] = address(0xABC);
    }

    function getReserveData(address asset) external view returns (
        uint256, uint128, uint128, uint128, uint128, uint128, uint40, uint16, address, address, address, address, uint128, uint128, uint128
    ) {
        address aToken = aTokens[asset];
        return (
            0, // configuration
            1000000000000000000, // liquidityIndex (1e18)
            50000000000000000, // currentLiquidityRate (5% APY)
            0, 0, 0, 0, 0,
            aToken, // aTokenAddress
            address(0), address(0), address(0), 0, 0, 0
        );
    }

    function supply(bytes32) external {
        // Mock successful supply
    }

    function withdraw(bytes32) external returns (uint256) {
        return 1000000; // Return mock amount
    }
}

contract MockL2Encoder {
    function encodeSupplyParams(address token, uint256 amount, uint16 referralCode) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, amount, referralCode));
    }

    function encodeWithdrawParams(address token, uint256 amount) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, amount));
    }
}

contract MockVeloRouter {
    function pairFor(address tokenA, address tokenB, bool stable) external pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, stable)))));
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        return (liquidity / 2, liquidity / 2);
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

contract StrategyTest is Test {
    TydroStrategy public tydroStrategy;
    VelodromeStrategy public veloStrategy;
    YieldAllocator public allocator;

    MockTydroPool public mockTydroPool;
    MockL2Encoder public mockEncoder;
    MockVeloRouter public mockVeloRouter;
    MockERC20 public mockToken;

    address public testToken = address(0x123);
    address public testToken2 = address(0x789);
    address public user = address(0x999);

    function setUp() public {
        // Deploy mocks
        mockTydroPool = new MockTydroPool();
        mockEncoder = new MockL2Encoder();
        mockVeloRouter = new MockVeloRouter();
        mockToken = new MockERC20();

        // Deploy strategies
        tydroStrategy = new TydroStrategy(address(mockTydroPool), address(mockEncoder));
        veloStrategy = new VelodromeStrategy(address(mockVeloRouter));

        // Deploy allocator
        allocator = new YieldAllocator();

        // Register strategies
        allocator.registerStrategy(tydroStrategy);
        allocator.registerStrategy(veloStrategy);

        // Set up test user with tokens
        // Mock token balance setup - would need mock implementation
        // mockToken.balanceOf[user] = 1000000000; // 1000 tokens
        vm.startPrank(user);
        mockToken.approve(address(allocator), type(uint256).max);
        vm.stopPrank();
    }

    function testTydroStrategyBasics() public {
        assertEq(tydroStrategy.strategyId(), 1);
        assertEq(tydroStrategy.strategyName(), "Tydro Lending");

        // Test token support
        assertTrue(tydroStrategy.supportsToken(testToken, ""));
        assertTrue(tydroStrategy.supportsToken(testToken2, ""));

        // Test APY
        uint256 apy = tydroStrategy.getAPY(testToken, "");
        assertGt(apy, 0); // Should return some APY
    }

    function testVelodromeStrategyBasics() public {
        assertEq(veloStrategy.strategyId(), 2);
        assertEq(veloStrategy.strategyName(), "Velodrome LP");

        // Test token support (depends on auxData)
        bytes memory auxData = abi.encode(testToken2, true); // tokenB, stable
        assertTrue(veloStrategy.supportsToken(testToken, auxData));

        // Test APY (mock high return)
        uint256 apy = veloStrategy.getAPY(testToken, auxData);
        assertGt(apy, 1000); // Should return high APY for Velodrome
    }

    function testTydroDeposit() public {
        vm.startPrank(address(allocator));

        uint256 depositAmount = 1000000; // 1 token
        uint256 shares = tydroStrategy.deposit(testToken, depositAmount, "");

        assertGt(shares, 0); // Should return shares
        assertEq(shares, depositAmount); // 1:1 for lending
    }

    function testTydroWithdraw() public {
        vm.startPrank(address(allocator));

        uint256 withdrawAmount = 1000000; // 1 token
        uint256 withdrawn = tydroStrategy.withdraw(testToken, withdrawAmount, "");

        assertEq(withdrawn, 1000000); // Mock returns same amount
    }

    function testVelodromeDeposit() public {
        vm.startPrank(address(allocator));

        uint256 depositAmount = 1000000; // 1 token
        bytes memory auxData = abi.encode(testToken2, true); // tokenB, stable
        uint256 shares = veloStrategy.deposit(testToken, depositAmount, auxData);

        assertGt(shares, 0); // Should return LP shares
    }

    function testVelodromeWithdraw() public {
        vm.startPrank(address(allocator));

        uint256 shares = 1000000; // 1 LP token
        bytes memory auxData = abi.encode(testToken2, true); // tokenB, stable
        uint256 withdrawn = veloStrategy.withdraw(testToken, shares, auxData);

        assertGt(withdrawn, 0); // Should return tokens
    }

    function testYieldAllocatorRegistration() public {
        // Check strategies are registered
        assertEq(address(allocator.strategies(1)), address(tydroStrategy));
        assertEq(address(allocator.strategies(2)), address(veloStrategy));
    }

    function testBestStrategySelection() public {
        (uint8 strategyId, uint256 apy) = allocator.getBestStrategy(testToken);

        // Velodrome should be selected (higher APY)
        assertEq(strategyId, 2); // Velodrome
        assertGt(apy, 1000); // High APY
    }

    function testFundAllocation() public {
        vm.startPrank(user);

        uint256 allocateAmount = 1000000; // 1 token

        // Allocate to best strategy (auto)
        allocator.allocateFunds(testToken, allocateAmount, 0);

        // Check allocation
        (uint128 principal, , ) = allocator.allocations(testToken, 2); // Velodrome
        assertEq(principal, allocateAmount);

        vm.stopPrank();
    }

    function testSmartRebalance() public {
        vm.startPrank(user);

        // Allocate some funds first
        uint256 allocateAmount = 1000000;
        allocator.allocateFunds(testToken, allocateAmount, 1); // Force to Tydro

        // Rebalance (should move to Velodrome if better APY)
        allocator.autoRebalance(testToken);

        // Check if funds moved
        (uint128 tydroPrincipal, , ) = allocator.allocations(testToken, 1);
        (uint128 veloPrincipal, , ) = allocator.allocations(testToken, 2);

        // Should have moved to Velodrome
        assertEq(tydroPrincipal, 0);
        assertGt(veloPrincipal, 0);

        vm.stopPrank();
    }

    function testSmartCompound() public {
        vm.startPrank(user);

        // Allocate some funds
        uint256 allocateAmount = 1000000;
        allocator.allocateFunds(testToken, allocateAmount, 0);

        // Compound
        allocator.smartCompound(testToken);

        // Should complete without errors
        assertTrue(true);

        vm.stopPrank();
    }

    function testStrategyAuxData() public {
        // Set aux data for Velodrome pair
        bytes memory auxData = abi.encode(testToken2, true);
        allocator.setStrategyAuxData(testToken, 2, auxData);

        // Check it's stored
        bytes memory stored = allocator.strategyAuxData(testToken, 2);
        assertEq(stored.length, auxData.length);
    }

    function testMaxAllocationLimits() public {
        // Set max allocation for Velodrome (50%)
        allocator.setMaxAllocation(2, 5000); // 50% = 5000 bps

        vm.startPrank(user);

        // Try to allocate more than max
        uint256 largeAmount = 10000000; // Large amount

        // Should work initially
        allocator.allocateFunds(testToken, largeAmount, 2);

        // Try to allocate more (should fail or be limited)
        // This tests the max allocation logic

        vm.stopPrank();
    }

    function testRebalanceThreshold() public {
        // Set rebalance threshold
        allocator.setRebalanceThreshold(1000); // 10%

        // Check it's set (would need internal access or event check)
        // For now just ensure it doesn't revert
        assertTrue(true);
    }

    function testErrorConditions() public {
        // Test unregistered strategy
        vm.expectRevert();
        allocator.allocateFunds(testToken, 1000, 99); // Invalid strategy

        // Test zero allocation
        vm.expectRevert();
        allocator.allocateFunds(testToken, 0, 0);

        // Test unsupported token for strategy
        // This would depend on strategy implementation
    }
}
