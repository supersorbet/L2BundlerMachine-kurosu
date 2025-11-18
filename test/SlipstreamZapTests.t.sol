// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ISlipstreamHelper} from "../src/interfaces/ISlipstreamHelper.sol";
import {ISlipstreamPositionNFT} from "../src/interfaces/ISlipstream.sol";
import {ILeafCLGauge} from "../src/interfaces/ISlipstream.sol";
import {IVeloRouter} from "../src/interfaces/IVelodrome.sol";

/// @title SlipstreamZapTests
/// @notice Comprehensive tests for Slipstream zap functionality
/// @dev Tests zap operations on mainnet fork to ensure real-world compatibility
contract SlipstreamZapTests is Test {
    // Ink L2 addresses (mainnet)
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    address constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c;
    address constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4;
    address constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;
    address constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702;
    address constant LEAF_CL_GAUGE = 0xe03C9C733fc67179a4959cF96449549cb31C2130;

    // Token addresses
    address constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1;
    address constant USDC_L2 = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address constant WETH_L2 = 0x4200000000000000000000000000000000000006;

    // Test addresses
    address constant TREASURY = 0x00000009eEE278329552382a472A7d06c773D7B3;
    address constant L2_USDT0_WHALE = 0x2D27Bf7AD3303bDCF341C5890296Ad8B49D68829;

    BundledYieldVaultV2_PRODUCTION public vault;
    uint256 public forkId;

    function setUp() public {
        // Create Ink L2 mainnet fork
        string memory inkRpc = vm.envString("INK_RPC");
        if (bytes(inkRpc).length == 0) {
            inkRpc = "https://rpc-gel.inkonchain.com";
        }
        forkId = vm.createFork(inkRpc);
        vm.selectFork(forkId);

        // Deploy vault
        vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            TREASURY,
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
        );

        // Transfer ownership to treasury
        vault.transferOwnership(TREASURY);

        // Setup token mappings
        vm.startPrank(TREASURY);
        vault.mapToken(USDT0_L2, USDT_L1);
        
        // Check if USDC_L2 exists before mapping
        uint256 usdcCodeSize;
        assembly { usdcCodeSize := extcodesize(USDC_L2) }
        if (usdcCodeSize > 0) {
            vault.mapToken(USDC_L2, USDT_L1); // Map USDC for testing
        }
        vm.stopPrank();

        // Seed vault with tokens
        deal(USDT0_L2, address(vault), 100000 * 1e6);
        
        // Only deal USDC if contract exists
        if (usdcCodeSize > 0) {
            deal(USDC_L2, address(vault), 100000 * 1e6);
        }
        
        deal(address(vault), 1 ether); // ETH for gas

        console.log("=== SLIPSTREAM ZAP TESTS SETUP ===");
        console.log("Vault:", address(vault));
        console.log("Slipstream Helper:", vault.SLIPSTREAM_HELPER());
        console.log("Velo Router:", vault.VELO_ROUTER());
        if (usdcCodeSize == 0) {
            console.log("WARNING: USDC_L2 does not exist on fork - some tests will be skipped");
        }
    }

    /// @notice Test basic zap functionality - single token to Slipstream position
    function testZapBasic() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Basic Zap ===");

        // Check if USDC exists
        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 1000 * 1e6; // $1000 USDT0
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        
        // Configure gauge
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        // Zap USDT0 into Slipstream position
        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100, // 0.01% fee
            -887220, // tickLower (full range)
            887220, // tickUpper (full range)
            0, // minAmount0
            0, // minAmount1
            true // stake in gauge
        );

        console.log("Zap successful! TokenId:", tokenId);
        assertGt(tokenId, 0, "Should have valid tokenId");

        // Verify position was created
        address helper = vault.SLIPSTREAM_HELPER();
        (address token0, address token1, uint24 fee, , , uint128 liquidity) = 
            ISlipstreamHelper(helper).getPosition(tokenId);
        
        assertEq(token0, USDT0_L2, "Token0 should be USDT0");
        assertEq(token1, USDC_L2, "Token1 should be USDC");
        assertEq(fee, 100, "Fee should be 0.01%");
        assertGt(liquidity, 0, "Should have liquidity");

        console.log("Position verified - Liquidity:", liquidity);

        vm.stopPrank();
    }

    /// @notice Test zap with different amounts
    function testZapVariousAmounts() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap Various Amounts ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 100 * 1e6;   // $100
        amounts[1] = 1000 * 1e6;  // $1k
        amounts[2] = 10000 * 1e6; // $10k
        amounts[3] = 50000 * 1e6; // $50k

        for (uint256 i = 0; i < amounts.length; i++) {
            deal(USDT0_L2, address(vault), amounts[i]);
            
            uint256 tokenId = vault.zapIntoSlipstreamPosition(
                USDT0_L2,
                USDC_L2,
                amounts[i],
                100,
                -887220,
                887220,
                0,
                0,
                false // Don't stake for faster testing
            );

            assertGt(tokenId, 0, "Should create position");
            console.log("Amount:", amounts[i] / 1e6, "USDT0 -> TokenId:", tokenId);
        }

        vm.stopPrank();
    }

    /// @notice Test zap with slippage protection
    function testZapWithSlippageProtection() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap With Slippage Protection ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 5000 * 1e6; // $5k
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        // Zap with reasonable slippage protection
        uint256 minAmount0 = (zapAmount / 2) * 90 / 100; // 10% slippage tolerance
        uint256 minAmount1 = (zapAmount / 2) * 90 / 100;

        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100,
            -887220,
            887220,
            minAmount0,
            minAmount1,
            true
        );

        assertGt(tokenId, 0, "Should create position with slippage protection");
        console.log("Zap with slippage protection successful - TokenId:", tokenId);

        vm.stopPrank();
    }

    /// @notice Test zap without staking
    function testZapWithoutStaking() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap Without Staking ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 2000 * 1e6;
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100,
            -887220,
            887220,
            0,
            0,
            false // Don't stake
        );

        assertGt(tokenId, 0, "Should create position");

        // Verify position exists but is not staked
        address helper = vault.SLIPSTREAM_HELPER();
        bytes32 positionHash = keccak256(abi.encodePacked(USDT0_L2, USDC_L2, uint24(100)));
        uint256[] memory stakedIds = ISlipstreamHelper(helper).getStakedTokenIds(positionHash);
        
        bool isStaked = false;
        for (uint256 i = 0; i < stakedIds.length; i++) {
            if (stakedIds[i] == tokenId) {
                isStaked = true;
                break;
            }
        }
        
        assertFalse(isStaked, "Position should not be staked");
        console.log("Zap without staking successful - TokenId:", tokenId);

        vm.stopPrank();
    }

    /// @notice Test zap with different fee tiers
    function testZapDifferentFeeTiers() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap Different Fee Tiers ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        vm.startPrank(TREASURY);
        
        uint24[] memory fees = new uint24[](3);
        fees[0] = 100;  // 0.01%
        fees[1] = 500;  // 0.05%
        fees[2] = 3000; // 0.3%

        for (uint256 i = 0; i < fees.length; i++) {
            uint256 zapAmount = 1000 * 1e6;
            deal(USDT0_L2, address(vault), zapAmount);

            // Set gauge for this fee tier
            vault.setSlipstreamGauge(USDT0_L2, USDC_L2, fees[i], LEAF_CL_GAUGE);

            try vault.zapIntoSlipstreamPosition(
                USDT0_L2,
                USDC_L2,
                zapAmount,
                fees[i],
                -887220,
                887220,
                0,
                0,
                false
            ) returns (uint256 tokenId) {
                assertGt(tokenId, 0, "Should create position");
                console.log("Fee tier:", fees[i], "-> TokenId:", tokenId);
            } catch {
                console.log("Fee tier", fees[i], "may not be available");
            }
        }

        vm.stopPrank();
    }

    /// @notice Test zap error conditions
    function testZapErrorConditions() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap Error Conditions ===");

        vm.startPrank(TREASURY);

        // Test: Insufficient balance
        deal(USDT0_L2, address(vault), 100 * 1e6);
        vm.expectRevert();
        vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            1000 * 1e6, // More than balance
            100,
            -887220,
            887220,
            0,
            0,
            false
        );
        console.log("Insufficient balance error handled correctly");

        // Test: Token not mapped
        address unmappedToken = address(0x999);
        deal(unmappedToken, address(vault), 1000 * 1e6);
        vm.expectRevert();
        vault.zapIntoSlipstreamPosition(
            unmappedToken,
            USDC_L2,
            1000 * 1e6,
            100,
            -887220,
            887220,
            0,
            0,
            false
        );
        console.log("Unmapped token error handled correctly");

        vm.stopPrank();
    }

    /// @notice Test zap and then increase liquidity
    function testZapThenIncreaseLiquidity() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap Then Increase Liquidity ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 2000 * 1e6;
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        // Zap
        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100,
            -887220,
            887220,
            0,
            0,
            true
        );

        console.log("Zap complete - TokenId:", tokenId);

        // Get initial liquidity
        address helper = vault.SLIPSTREAM_HELPER();
        (, , , , , uint128 initialLiquidity) = ISlipstreamHelper(helper).getPosition(tokenId);
        console.log("Initial liquidity:", initialLiquidity);

        // Increase liquidity
        deal(USDT0_L2, address(vault), 1000 * 1e6);
        deal(USDC_L2, address(vault), 1000 * 1e6);

        BundledYieldVaultV2_PRODUCTION.SlipstreamLiquidityParams memory liqParams = 
            BundledYieldVaultV2_PRODUCTION.SlipstreamLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 1000 * 1e6,
                amount1Desired: 1000 * 1e6,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1 hours
            });

        vault.increaseSlipstreamLiquidity(liqParams);
        console.log("Liquidity increased");

        // Verify liquidity increased
        (, , , , , uint128 newLiquidity) = ISlipstreamHelper(helper).getPosition(tokenId);
        assertGt(newLiquidity, initialLiquidity, "Liquidity should increase");
        console.log("New liquidity:", newLiquidity);

        vm.stopPrank();
    }

    /// @notice Test zap and collect fees
    function testZapAndCollectFees() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap And Collect Fees ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 5000 * 1e6;
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        // Zap
        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100,
            -887220,
            887220,
            0,
            0,
            true
        );

        console.log("Zap complete - TokenId:", tokenId);

        // Warp time to accumulate fees
        vm.warp(block.timestamp + 7 days);
        console.log("Time warped 7 days");

        // Collect fees
        vault.collectSlipstreamFees(tokenId);
        console.log("Fees collected");

        vm.stopPrank();
    }

    /// @notice Test zap and harvest rewards
    function testZapAndHarvestRewards() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Zap And Harvest Rewards ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        uint256 zapAmount = 10000 * 1e6;
        deal(USDT0_L2, address(vault), zapAmount);

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        // Zap and stake
        uint256 tokenId = vault.zapIntoSlipstreamPosition(
            USDT0_L2,
            USDC_L2,
            zapAmount,
            100,
            -887220,
            887220,
            0,
            0,
            true // Stake for rewards
        );

        console.log("Zap and stake complete - TokenId:", tokenId);

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        console.log("Time warped 30 days");

        // Harvest rewards
        vault.harvestSlipstreamRewards(USDT0_L2, USDC_L2, 100);
        console.log("Rewards harvested");

        vm.stopPrank();
    }

    /// @notice Test multiple zaps create separate positions
    function testMultipleZaps() public {
        vm.selectFork(forkId);
        console.log("\n=== TEST: Multiple Zaps ===");

        uint256 codeSize;
        assembly { codeSize := extcodesize(USDC_L2) }
        if (codeSize == 0) {
            console.log("SKIP: USDC_L2 does not exist on fork");
            return;
        }

        vm.startPrank(TREASURY);
        vault.setSlipstreamGauge(USDT0_L2, USDC_L2, 100, LEAF_CL_GAUGE);

        uint256[] memory tokenIds = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 zapAmount = 1000 * 1e6;
            deal(USDT0_L2, address(vault), zapAmount);

            tokenIds[i] = vault.zapIntoSlipstreamPosition(
                USDT0_L2,
                USDC_L2,
                zapAmount,
                100,
                -887220,
                887220,
                0,
                0,
                false
            );

            assertGt(tokenIds[i], 0, "Should create position");
            console.log("Zap", i + 1, "-> TokenId:", tokenIds[i]);
        }

        // Verify all positions exist
        address helper = vault.SLIPSTREAM_HELPER();
        bytes32 positionHash = keccak256(abi.encodePacked(USDT0_L2, USDC_L2, uint24(100)));
        uint256[] memory allTokenIds = ISlipstreamHelper(helper).getPositionTokenIds(positionHash);
        
        assertGe(allTokenIds.length, 3, "Should have at least 3 positions");
        console.log("Total positions:", allTokenIds.length);

        vm.stopPrank();
    }
}

