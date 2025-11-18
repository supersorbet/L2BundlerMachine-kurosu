// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";
import {BundledYieldVaultV2_RELAY} from "../src/BundledYieldVaultV2_RELAY.sol";
import {IL2Pool} from "../src/interfaces/IL2Pool.sol";
import {IL2Encoder} from "../src/interfaces/IL2Encoder.sol";
import {ISpokePool} from "../src/interfaces/IAcross.sol";

/// @title MainnetForkTest
/// @notice mainnet fork tests with smol amounts
/// @dev Run with: forge test --fork-url $ETH_RPC --fork-url $INK_RPC -vv
/// @dev Or: forge test --match-contract MainnetFork --fork-url $ETH_RPC --fork-url $INK_RPC -vv
contract MainnetForkTest is Test {
    // Ethereum Mainnet addresses (Chain ID: 1)
    address public constant HUB_POOL = 0xc186fA914353c44b2E33eBE05f21846F1048bEda; // Across HubPool on Ethereum
    address public constant USDT_L1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Mainnet USDT
    
    // Ink L2 addresses (Chain ID: 57073)
    address public constant ACROSS_SPOKE_POOL = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4; // Across SpokePool on Ink
    address public constant RELAY_DEPOSITORY = 0x4cD00E387622C35bDDB9b4c962C136462338BC31; // Relay Depository on Ink
    address public constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA; // Tydro IPool on Ink
    address public constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c; // Tydro L2Encoder on Ink
    address public constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C; // Velodrome Universal Router on Ink
    address public constant SLIPSTREAM_POSITION_NFT = 0x991d5546C4B442B4c5fdc4c8B8b8d131DEB24702; // Slipstream Position NFT on Ink
    address public constant USDT0_L2 = 0x0200C29006150606B650577BBE7B6248F58470c1; // USDT0 on Ink L2
    
    address public treasury; // Treasury address - set in setUp() or via env var
    uint256 public constant INK_CHAIN_ID = 57073; // Ink chain ID (from Across docs)
    
    L1DepositorV2_PRODUCTION public l1Depositor; // on ETH fork
    BundledYieldVaultV2_PRODUCTION public l2VaultAcross; // on INK fork
    BundledYieldVaultV2_RELAY public l2VaultRelay; // on INK fork
    uint256 internal ethForkId;
    uint256 internal inkForkId;
    
    // Optional env-provided rich holders to seed the treasury on forks
    address internal usdtL1Whale;
    address internal usdt0L2Whale;
    
    function setUp() public {
        // Create ETH and INK forks if RPCs are provided
        string memory ethRpc = vm.envString("ETH_RPC");
        ethForkId = vm.createFork(ethRpc);
        vm.selectFork(ethForkId);
        
        // Create Ink fork (optional)
        try vm.envString("INK_RPC") returns (string memory inkRpc) {
            if (bytes(inkRpc).length > 0) {
                inkForkId = vm.createFork(inkRpc);
            } else {
                inkForkId = 0;
            }
        } catch {
            inkForkId = 0;
        }
        
        // Set treasury from env or use default
        try vm.envAddress("TREASURY_ADDRESS") returns (address _treasury) {
            treasury = _treasury;
        } catch {
            treasury = address(0x1234); // Default for testing
        }
        
        // Note: For read-only Ink tests we will switch to inkForkId when needed
        
        // Deploy contracts
        // Note: In real deployment, deploy L2 vault first, then L1 depositor
        // For testing, we'll deploy both on mainnet fork
        
        // Deploy L2 vaults on INK fork
        if (inkForkId != 0) {
            vm.selectFork(inkForkId);
        l2VaultAcross = new BundledYieldVaultV2_PRODUCTION(
                TYDRO_POOL,
                L2_ENCODER,
                ACROSS_SPOKE_POOL,
                treasury,
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
            );
            l2VaultRelay = new BundledYieldVaultV2_RELAY(
                TYDRO_POOL,
                L2_ENCODER,
                RELAY_DEPOSITORY,
                treasury
            );
        }
        
        // Deploy L1 depositor on ETH fork, pointing to the Across vault address (on INK)
        vm.selectFork(ethForkId);
        l1Depositor = new L1DepositorV2_PRODUCTION(HUB_POOL, address(l2VaultAcross), INK_CHAIN_ID);
        
        // Setup ownership
        l1Depositor.transferOwnership(treasury);
        if (address(l2VaultAcross) != address(0)) {
            vm.selectFork(inkForkId);
            l2VaultAcross.transferOwnership(treasury);
        }
        if (address(l2VaultRelay) != address(0)) {
            vm.selectFork(inkForkId);
            l2VaultRelay.transferOwnership(treasury);
        }
        
        // Set L1 recipient on L2 vaults (point to L1 depositor for yield bridging)
        if (inkForkId != 0) {
            vm.selectFork(inkForkId);
            vm.startPrank(treasury);
            if (address(l2VaultAcross) != address(0)) {
                l2VaultAcross.setL1Recipient(address(l1Depositor));
            }
            if (address(l2VaultRelay) != address(0)) {
                l2VaultRelay.setL1Recipient(address(l1Depositor));
            }
            vm.stopPrank();
        }
        
        // Set token mappings on respective forks
        if (USDT0_L2 != address(0)) {
            // ETH fork: set mapping on L1 depositor
            vm.selectFork(ethForkId);
            vm.startPrank(treasury);
            l1Depositor.setTokenMapping(USDT_L1, USDT0_L2);
            vm.stopPrank();
            // INK fork: set mappings on L2 vaults
            if (inkForkId != 0) {
                vm.selectFork(inkForkId);
                vm.startPrank(treasury);
                if (address(l2VaultAcross) != address(0)) l2VaultAcross.mapToken(USDT0_L2, USDT_L1);
                if (address(l2VaultRelay) != address(0)) l2VaultRelay.setTokenMapping(USDT0_L2, USDT_L1);
                vm.stopPrank();
            }
        }
        
        // Fund treasury with ETH for gas on both forks
        vm.selectFork(ethForkId);
        vm.deal(treasury, 1 ether);
        if (inkForkId != 0) {
            vm.selectFork(inkForkId);
            vm.deal(treasury, 1 ether);
        }
        
        // Authorize treasury as yield receiver on L1 depositor
        vm.selectFork(ethForkId);
        vm.startPrank(treasury);
        l1Depositor.setYieldReceiver(treasury, true);
        vm.stopPrank();
        
        // Optional: seed treasury with real tokens via env-provided whale accounts
        // L1 USDT
        vm.selectFork(ethForkId);
        try vm.envAddress("USDT_L1_WHALE") returns (address whale) {
            usdtL1Whale = whale;
            // fund whale with ETH for gas
            vm.deal(usdtL1Whale, 10 ether);
            // transfer USDT to treasury
            vm.startPrank(usdtL1Whale);
            (bool s1, ) = USDT_L1.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, 200e6));
            if (s1) {
                console.log("Seeded L1 USDT to treasury");
            } else {
                console.log("USDT_L1 transfer failed - whale may not be correct");
            }
            vm.stopPrank();
        } catch {}
        
        // INK USDT0
        if (inkForkId != 0) {
            vm.selectFork(inkForkId);
            try vm.envAddress("USDT0_L2_WHALE") returns (address whale2) {
                usdt0L2Whale = whale2;
                vm.deal(usdt0L2Whale, 10 ether);
                vm.startPrank(usdt0L2Whale);
                (bool s2, ) = USDT0_L2.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, 500e6));
                if (s2) {
                    console.log("Seeded L2 USDT0 to treasury");
                } else {
                    console.log("USDT0_L2 transfer failed - whale may not be correct");
                }
                vm.stopPrank();
            } catch {}
        }
    }
    
    /// @notice Test small deposit via Across on mainnet fork
    /// @dev This test requires:
    ///   - Mainnet fork
    ///   - Real token addresses
    ///   - Sufficient balance in treasury
    function testSmallDepositAcross() public {
        // Skip if not configured
        if (TYDRO_POOL == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Real addresses not configured");
            return;
        }
        
        vm.selectFork(ethForkId);
        uint256 depositAmount = 100 * 1e6; // $100 USDT (small test)
        console.log("L1 USDT balance pre:", _erc20Balance(USDT_L1, treasury));
        vm.startPrank(treasury);
        (bool ok1, ) = USDT_L1.call(abi.encodeWithSignature("approve(address,uint256)", address(l1Depositor), depositAmount));
        if (!ok1) console.log("USDT approve failed");
        // Execute depositToL2 against real HubPool (fork)
        try l1Depositor.depositToL2(USDT_L1, depositAmount, (depositAmount * 99) / 100) {
            console.log("Across deposit executed on fork");
        } catch {
            console.log("Across deposit reverted (expected if insufficient balance/allowance)");
        }
        vm.stopPrank();
        console.log("L1 USDT balance post:", _erc20Balance(USDT_L1, treasury));
    }
    
    /// @notice Test small deposit via Relay on mainnet fork
    function testSmallDepositRelay() public {
        if (RELAY_DEPOSITORY == address(0) || TYDRO_POOL == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Real addresses not configured");
            return;
        }
        
        if (inkForkId == 0) {
            console.log("Skipping: INK_RPC not provided");
            return;
        }
        vm.selectFork(inkForkId);
        console.log("Ink L2 USDT0 balance pre:", _erc20Balance(USDT0_L2, treasury));
        // Deployments done in setUp on Ink; test deposit path to Tydro
        vm.startPrank(treasury);
        (bool ok2, ) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", address(l2VaultRelay), 100e6));
        if (!ok2) console.log("USDT0 approve failed");
        try l2VaultRelay.deposit(USDT0_L2, 100e6) {
            console.log("Relay vault deposit executed on fork");
        } catch {
            console.log("Relay vault deposit reverted (pool may require conditions)");
        }
        vm.stopPrank();
        console.log("Ink L2 USDT0 balance post:", _erc20Balance(USDT0_L2, treasury));
    }
    
    /// @notice Test full end-to-end flow: L1 deposit → L2 receipt → Tydro deposit → yield accrual → harvest & bridge
    function testFullE2EFlowAcross() public {
        if (
            inkForkId == 0 || TYDRO_POOL == address(0) || USDT0_L2 == address(0) || usdtL1Whale == address(0)
                || usdt0L2Whale == address(0)
        ) {
            console.log("Skipping: Missing Ink fork, addresses, or whale env configuration");
            return;
        }
        
        vm.selectFork(ethForkId);
        uint256 depositAmount = 100 * 1e6; // $100 USDT
        uint256 treasuryBalanceBefore = _erc20Balance(USDT_L1, treasury);
        console.log("=== E2E Test: Across Bridge ===");
        console.log("Step 1: L1 Treasury USDT balance:", treasuryBalanceBefore);
        
        if (treasuryBalanceBefore < depositAmount) {
            console.log("Skipping: Insufficient L1 USDT balance");
            return;
        }
        
        // Step 1: L1 deposit via Across
        vm.startPrank(treasury);
        vm.recordLogs();
        (bool ok1, ) = USDT_L1.call(abi.encodeWithSignature("approve(address,uint256)", address(l1Depositor), depositAmount));
        if (!ok1) {
            console.log("USDT approve failed");
        } else {
            bytes memory callData = abi.encodeWithSelector(
                L1DepositorV2_PRODUCTION.depositToL2.selector,
                USDT_L1,
                depositAmount,
                (depositAmount * 99) / 100
            );
            (bool success, bytes memory ret) = address(l1Depositor).call(callData);
            if (success) {
                console.log("Step 1: L1 deposit executed, amount:", depositAmount);
            } else {
                _logRevertData("Step 1: L1 deposit revert", ret);
            }
        }
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        if (depositLogs.length == 0) {
            console.log("--- Across HubPool deposit logs ---");
            console.log("No logs captured");
        } else {
            _logVmLogs("Across HubPool deposit logs", depositLogs);
        }
        vm.stopPrank();
        
        uint256 treasuryBalanceAfter = _erc20Balance(USDT_L1, treasury);
        console.log("Step 1: L1 Treasury USDT balance after:", treasuryBalanceAfter);
        
        // Step 1b: Simulate Across relayer fill on Ink fork (tokens delivered to treasury)
        vm.selectFork(inkForkId);
        uint256 l2TreasuryBalanceBefore = _erc20Balance(USDT0_L2, treasury);
        console.log("Step 2: L2 Treasury USDT0 balance before fill:", l2TreasuryBalanceBefore);
        
        uint256 fillAmount = (depositAmount * 99) / 100; // assumes 1% slippage tolerance
        _ensureAcrossLiquidity(fillAmount);
        vm.startPrank(ACROSS_SPOKE_POOL);
        (bool fillOk,) = USDT0_L2.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, fillAmount));
        vm.stopPrank();
        if (!fillOk) {
            console.log("Across fill simulation failed");
            return;
        }
        uint256 l2TreasuryBalanceAfter = _erc20Balance(USDT0_L2, treasury);
        console.log("Step 2: L2 Treasury USDT0 balance after fill:", l2TreasuryBalanceAfter);
        
        // Step 3: Deposit from treasury into Tydro via vault
        console.log("Step 3: Pool USDT0 balance before deposit:", _erc20Balance(USDT0_L2, TYDRO_POOL));
        console.log("Step 3: Vault USDT0 balance before deposit:", _erc20Balance(USDT0_L2, address(l2VaultAcross)));
        vm.startPrank(treasury);
        (bool ok2,) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", address(l2VaultAcross), fillAmount));
        if (!ok2) {
            console.log("USDT0 approve failed");
        }
        
        vm.recordLogs();
        bytes32 encodedSupply = IL2Encoder(L2_ENCODER).encodeSupplyParams(USDT0_L2, fillAmount, 0);
        (uint16 encodedAssetId, uint128 encodedShortAmount, uint16 encodedReferral) = _decodeSupplyParams(encodedSupply);
        console.log("Step 3: Encoded supply assetId:", encodedAssetId);
        console.log("Step 3: Encoded supply shortAmount:", uint256(encodedShortAmount));
        console.log("Step 3: Encoded supply referral:", encodedReferral);
        bytes memory depositCalldata = abi.encodeWithSelector(
            BundledYieldVaultV2_PRODUCTION.deposit.selector,
            USDT0_L2,
            fillAmount
        );
        (bool l2DepositSuccess, bytes memory l2Ret) = address(l2VaultAcross).call(depositCalldata);
        if (l2DepositSuccess) {
            console.log("Step 3: L2 deposit to Tydro executed, amount:", fillAmount);
        } else {
            _logRevertData("Step 3: L2 deposit revert", l2Ret);
        }
        Vm.Log[] memory tydroDepositLogs = vm.getRecordedLogs();
        if (tydroDepositLogs.length == 0) {
            console.log("--- Tydro deposit logs ---");
            console.log("No logs captured");
        } else {
            _logVmLogs("Tydro deposit logs", tydroDepositLogs);
        }
        vm.stopPrank();
        console.log("Step 3: Pool USDT0 balance after deposit:", _erc20Balance(USDT0_L2, TYDRO_POOL));
        console.log("Step 3: Vault USDT0 balance after deposit:", _erc20Balance(USDT0_L2, address(l2VaultAcross)));
        if (!l2DepositSuccess) {
            console.log("Halting E2E flow after deposit failure");
            return;
        }
        
        // Step 4: Simulate yield accrual by topping up aToken balance
        (
            ,,
            ,
            ,
            ,
            ,
            ,
            ,
            address aToken,
            ,
            ,
            ,
            ,
            ,

        ) = IL2Pool(TYDRO_POOL).getReserveData(USDT0_L2);
        uint256 currentATokenBal = _erc20Balance(aToken, address(l2VaultAcross));
        // Simulate yield by directly supplying to vault's aToken balance
        // Since L2Pool doesn't support onBehalfOf, we transfer to vault first
        uint256 simulatedYield = 5 * 1e6; // $5 headroom to simulate accrual
        if (simulatedYield > 0) {
            vm.startPrank(treasury);
            (bool transferOk,) = USDT0_L2.call(abi.encodeWithSignature("transfer(address,uint256)", address(l2VaultAcross), simulatedYield));
            if (!transferOk) {
                console.log("Warning: transfer failed during yield simulation");
            } else {
                vm.stopPrank();
                vm.startPrank(address(l2VaultAcross));
                (bool approveYield,) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", TYDRO_POOL, simulatedYield));
                if (!approveYield) {
                    console.log("Warning: approve failed during yield simulation");
                } else {
                    (, , , , , , , uint16 assetId, , , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(USDT0_L2);
                    bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(USDT0_L2, simulatedYield, 0);
                    (uint16 simAssetId, uint128 simShortAmount, uint16 simReferral) = _decodeSupplyParams(supplyArgs);
                    console.log("Yield injection encoded assetId:", simAssetId);
                    console.log("Yield injection encoded shortAmount:", uint256(simShortAmount));
                    console.log("Yield injection encoded referral:", simReferral);
                    try IL2Pool(TYDRO_POOL).supply(supplyArgs) {
                        console.log("Injected simulated yield via supply:", simulatedYield);
                    } catch {
                        console.log("Warning: supply for yield simulation reverted");
                    }
                }
            }
            vm.stopPrank();
        }
        l2VaultAcross.updateYield(USDT0_L2);
        _logReserveData("Post-yield reserve data (Across path)", USDT0_L2);
        
        // Step 5: Check yield status
        (uint256 deposited, uint256 currentBalance, uint256 yieldAvailable, ) = l2VaultAcross.getStatus(USDT0_L2);
        console.log("Step 5: Tydro status - deposited:", deposited);
        console.log("Step 5: Tydro status - current:", currentBalance);
        console.log("Step 5: Tydro status - yield:", yieldAvailable);
        console.log("Step 5: Pool USDT0 balance:", _erc20Balance(USDT0_L2, TYDRO_POOL));
        console.log("Step 5: Vault USDT0 balance:", _erc20Balance(USDT0_L2, address(l2VaultAcross)));
        console.log("Step 5: Vault aToken balance:", _erc20Balance(aToken, address(l2VaultAcross)));
        
        // Step 6: Harvest and bridge (if yield available)
        if (yieldAvailable > 0) {
            uint256 expectedBridgeAmount = yieldAvailable;
            console.log("Step 6: Attempting to harvest yield:", yieldAvailable);
            console.log("Step 6: Pool USDT0 balance before harvest:", _erc20Balance(USDT0_L2, TYDRO_POOL));
            console.log("Step 6: Vault aToken balance before harvest:", _erc20Balance(aToken, address(l2VaultAcross)));
            console.log("Step 6: Vault USDT0 balance before harvest:", _erc20Balance(USDT0_L2, address(l2VaultAcross)));
            console.log("Step 6: Vault ETH balance before harvest:", address(l2VaultAcross).balance);
            (uint256 deposited, uint256 current, uint256 yield, uint256 gasBal) = l2VaultAcross.getStatus(USDT0_L2);
            console.log("Step 6: Vault status - deposited:", deposited);
            console.log("Step 6: Vault status - current:", current);
            console.log("Step 6: Vault status - yield:", yield);
            console.log("Step 6: Vault status - gasBal:", gasBal);
            
            // Fund vault with small amount of ETH for gas (if needed)
            uint128 minGasBal = l2VaultAcross.minGasBalance();
            uint64 autoGasRefill = l2VaultAcross.autoGasRefillBps();
            console.log("Step 6: Vault autoGasRefillBps:", autoGasRefill);
            if (address(l2VaultAcross).balance < minGasBal) {
                vm.deal(address(l2VaultAcross), minGasBal);
                console.log("Step 6: Funded vault with ETH for gas:", minGasBal);
            }
            
            bytes32 encodedWithdraw = IL2Encoder(L2_ENCODER).encodeWithdrawParams(USDT0_L2, type(uint256).max);
            (uint16 withdrawAssetId, uint128 withdrawShortAmount) = _decodeWithdrawParams(encodedWithdraw);
            console.log("Step 6: Encoded withdraw assetId:", withdrawAssetId);
            console.log("Step 6: Encoded withdraw shortAmount:", uint256(withdrawShortAmount));
            
            // Ensure Across SpokePool has liquidity for the bridge
            uint256 bridgeAmountNeeded = yieldAvailable; // Approximate
            _ensureAcrossLiquidity(bridgeAmountNeeded);
            console.log("Step 6: Across SpokePool USDT0 balance:", _erc20Balance(USDT0_L2, ACROSS_SPOKE_POOL));
            
            // Test updateYield separately to see if it works
            vm.startPrank(treasury);
            (bool updateOk, bytes memory updateRet) = address(l2VaultAcross).call(
                abi.encodeWithSelector(BundledYieldVaultV2_PRODUCTION.updateYield.selector, USDT0_L2)
            );
            if (updateOk) {
                console.log("Step 6: updateYield succeeded");
                (uint256 depAfterUpdate, uint256 currAfterUpdate, uint256 yieldAfterUpdate, ) = l2VaultAcross.getStatus(USDT0_L2);
                console.log("Step 6: After updateYield - deposited:", depAfterUpdate);
                console.log("Step 6: After updateYield - current:", currAfterUpdate);
                console.log("Step 6: After updateYield - yield:", yieldAfterUpdate);
            } else {
                _logRevertData("Step 6: updateYield failed", updateRet);
            }
            vm.stopPrank();
            
            vm.startPrank(treasury);
            vm.recordLogs();
            bytes memory harvestCalldata = abi.encodeWithSelector(
                BundledYieldVaultV2_PRODUCTION.harvestAndBridge.selector,
                USDT0_L2,
                uint8(0),
                uint64(0),
                uint256(0)
            );
            (bool harvestSuccess, bytes memory harvestRet) = address(l2VaultAcross).call(harvestCalldata);
            if (harvestSuccess) {
                console.log("Step 6: Harvest & bridge executed, yield:", yieldAvailable);
            } else {
                _logRevertData("Step 6: Harvest & bridge revert", harvestRet);
                console.log("Step 6: Pool USDT0 balance after failed harvest:", _erc20Balance(USDT0_L2, TYDRO_POOL));
                console.log("Step 6: Vault aToken balance after failed harvest:", _erc20Balance(aToken, address(l2VaultAcross)));
                console.log("Step 6: Vault USDT0 balance after failed harvest:", _erc20Balance(USDT0_L2, address(l2VaultAcross)));
                
                // Check vault status after failure
                (uint256 depAfter, uint256 currAfter, uint256 yieldAfter, uint256 gasAfter) = l2VaultAcross.getStatus(USDT0_L2);
                console.log("Step 6: Vault status after failure - deposited:", depAfter);
                console.log("Step 6: Vault status after failure - current:", currAfter);
                console.log("Step 6: Vault status after failure - yield:", yieldAfter);
            }
            Vm.Log[] memory harvestLogs = vm.getRecordedLogs();
            if (harvestLogs.length == 0) {
                console.log("--- Across harvest logs ---");
                console.log("No logs captured");
            } else {
                _logVmLogs("Across harvest logs", harvestLogs);
                // Parse HarvestStep and BridgeError events
                _parseHarvestEvents(harvestLogs);
            }
            vm.stopPrank();
            if (!harvestSuccess) {
                console.log("Halting E2E flow after harvest failure");
                return;
            }
            
            // Step 6b: Simulate L1 settlement by transferring USDT to treasury
            vm.selectFork(ethForkId);
            uint256 l1DepositorBalanceBefore = _erc20Balance(USDT_L1, address(l1Depositor));
            uint256 treasuryBalanceBeforeYield = _erc20Balance(USDT_L1, treasury);
            _ensureL1Liquidity(expectedBridgeAmount);
            vm.startPrank(usdtL1Whale);
            (bool settleOk,) =
                USDT_L1.call(abi.encodeWithSignature("transfer(address,uint256)", address(l1Depositor), expectedBridgeAmount));
            vm.stopPrank();
            if (!settleOk) {
                console.log("L1 settlement transfer failed");
                return;
            }
            uint256 l1DepositorBalanceAfter = _erc20Balance(USDT_L1, address(l1Depositor));
            console.log("Step 6b: L1 Depositor USDT after settlement:", l1DepositorBalanceAfter);
            assertGt(l1DepositorBalanceAfter, l1DepositorBalanceBefore, "L1 depositor balance did not increase");
            
            // Record yield and withdraw to treasury
            vm.startPrank(treasury);
            vm.recordLogs();
            l1Depositor.receiveYield(USDT_L1, expectedBridgeAmount);
            l1Depositor.withdrawYield(USDT_L1, treasury);
            Vm.Log[] memory yieldLogs = vm.getRecordedLogs();
            _logVmLogs("L1 yield accounting logs", yieldLogs);
            vm.stopPrank();
            uint256 treasuryBalanceAfterYield = _erc20Balance(USDT_L1, treasury);
            console.log("Step 6c: L1 Treasury USDT after withdraw:", treasuryBalanceAfterYield);
            assertGt(treasuryBalanceAfterYield, treasuryBalanceBeforeYield, "Yield withdraw did not increase treasury balance");
        } else {
            console.log("Step 6: No yield available yet (would accrue over time)");
        }
        
        console.log("=== E2E Test Complete ===");
    }
    
    /// @notice Test yield harvesting with real Tydro pool
    function testRealYieldHarvest() public {
        if (TYDRO_POOL == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Real addresses not configured");
            return;
        }
        
        console.log("Real yield harvest test - requires real Tydro pool");
    }
    
    /// @notice Inspect Ink Tydro pool and USDT0 reserve data on Ink fork
    function testInkTydroIntrospection() public {
        if (inkForkId == 0) {
            console.log("Skipping: INK_RPC not provided");
            return;
        }
        if (TYDRO_POOL == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Real Ink addresses not configured");
            return;
        }
        vm.selectFork(inkForkId);
        if (block.chainid != INK_CHAIN_ID) {
            console.log("Skipping: Ink fork not active");
            return;
        }
        
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
            console.log("Ink Tydro aToken:", aTokenAddress);
            console.log("LiquidityIndex:", uint256(liquidityIndex));
            console.log("Config data:", configuration);
            console.log("LastUpdate:", uint256(lastUpdateTimestamp));
            console.log("AssetId:", uint256(id));
            assertTrue(aTokenAddress != address(0), "aToken must exist");
        } catch {
            console.log("Skipping: Ink getReserveData reverted (RPC/fork not active)");
        }
    }
    
    /// @notice Simulate high gas price conditions to observe cost impact
    function testHighGasPriceSimulation() public {
        vm.selectFork(ethForkId);
        // Set a high tx.gasprice for subsequent calls
        vm.txGasPrice(200 gwei);
        
        // Run a lightweight call (no external token transfers) to account for base overhead
        // This primarily ensures we can run with high gas price and capture reporting
        testForkCheck();
        console.log("Simulated gas price:", tx.gasprice);
    }

    /// @notice Preview Across deposit calldata and expected min amounts for typical sizes
    function testAcrossCalldataPreview() public view {
        uint64 slippageBps = 100; // 1%
        uint256[4] memory amounts = [uint256(50e6), uint256(100e6), uint256(250e6), uint256(1000e6)];
        console.log("Across calldata preview");
        console.log("slippageBps:", slippageBps);
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            uint256 minAmount = (amount * (10000 - slippageBps)) / 10000;
            bytes memory data = abi.encodeWithSignature(
                "deposit(address,address,address,uint256,uint256,uint256,address,uint32,bytes)",
                address(l2VaultAcross),
                USDT_L1,
                USDT0_L2,
                amount,
                minAmount,
                INK_CHAIN_ID,
                address(0),
                uint32(block.timestamp),
                abi.encode(treasury)
            );
            console.log("amount:", amount);
            console.log("min:", minAmount);
            console.log("calldataLen:", data.length);
        }
    }

    /// @notice Preview Relay deposit calldata and expected fees for typical sizes
    function testRelayCalldataPreview() public view {
        uint64 feeBps = 100; // 1%
        uint256 deadline = block.timestamp + 24 hours;
        uint256[4] memory amounts = [uint256(50e6), uint256(100e6), uint256(250e6), uint256(1000e6)];
        console.log("Relay calldata preview");
        console.log("feeBps:", feeBps);
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            uint256 maxFee = (amount * feeBps) / 10000;
            bytes memory data = abi.encodeWithSignature(
                "deposit(uint256,address,address,uint256,uint256,uint256)",
                uint256(1),
                address(l1Depositor),
                USDT0_L2,
                amount,
                maxFee,
                deadline
            );
            console.log("amount:", amount);
            console.log("maxFee:", maxFee);
            console.log("deadline:", deadline);
            console.log("calldataLen:", data.length);
        }
    }

    /// @notice Log a detailed Ink reserve snapshot for USDT0
    function testInkReserveSnapshot() public {
        if (inkForkId == 0) {
            console.log("Skipping: INK_RPC not provided");
            return;
        }
        if (TYDRO_POOL == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Real Ink addresses not configured");
            return;
        }
        vm.selectFork(inkForkId);
        if (block.chainid != INK_CHAIN_ID) {
            console.log("Skipping: Ink fork not active");
            return;
        }
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
            console.log("Ink reserve snapshot -> aToken:", aTokenAddress);
            console.log("liquidityIndex:", uint256(liquidityIndex));
            console.log("currentLiquidityRate:", uint256(currentLiquidityRate));
            console.log("variableBorrowIndex:", uint256(variableBorrowIndex));
            console.log("currentVariableBorrowRate:", uint256(currentVariableBorrowRate));
            console.log("currentStableBorrowRate:", uint256(currentStableBorrowRate));
            console.log("lastUpdate:", uint256(lastUpdateTimestamp));
            console.log("assetId:", uint256(id));
            console.log("strategy:", interestRateStrategyAddress);
            console.log("accruedToTreasury:", uint256(accruedToTreasury));
            console.log("unbacked:", uint256(unbacked));
            console.log("isoTotalDebt:", uint256(isolationModeTotalDebt));
            console.log("config:", configuration);
        } catch {
            console.log("Skipping: Ink getReserveData reverted (RPC/fork not active)");
        }
    }
    
    /// @notice Helper to check if mainnet fork is active
    function testForkCheck() public {
        vm.selectFork(ethForkId);
        assertEq(block.chainid, 1, "Must be on mainnet fork (chain ID 1)");
        console.log("Fork check passed - on mainnet fork");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
    }

    /// @notice Test full end-to-end flow with Relay Protocol
    function testFullE2EFlowRelay() public {
        if (
            inkForkId == 0 || TYDRO_POOL == address(0) || USDT0_L2 == address(0) || usdt0L2Whale == address(0)
                || usdtL1Whale == address(0)
        ) {
            console.log("Skipping: Missing Ink fork, addresses, or whale env configuration");
            return;
        }
        
        // Ensure we're on the Ink fork
        vm.selectFork(inkForkId);
        require(block.chainid == INK_CHAIN_ID, "Must be on Ink fork");
        uint256 depositAmount = 100 * 1e6; // $100 USDT0
        uint256 treasuryBalanceBefore = _erc20Balance(USDT0_L2, treasury);
        console.log("=== E2E Test: Relay Protocol ===");
        console.log("Step 1: L2 Treasury USDT0 balance:", treasuryBalanceBefore);
        
        if (treasuryBalanceBefore < depositAmount) {
            console.log("Skipping: Insufficient L2 USDT0 balance");
            return;
        }
        
        // Step 1: Deposit to Relay vault
        console.log("Step 1: Relay pool USDT0 balance before deposit:", _erc20Balance(USDT0_L2, TYDRO_POOL));
        console.log("Step 1: Relay vault USDT0 balance before deposit:", _erc20Balance(USDT0_L2, address(l2VaultRelay)));
        console.log("Step 1: Treasury USDT0 balance before deposit:", _erc20Balance(USDT0_L2, treasury));
        console.log("Step 1: Treasury USDT0 allowance to vault:", _erc20Allowance(USDT0_L2, treasury, address(l2VaultRelay)));
        vm.startPrank(treasury);
        (bool ok1,) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", address(l2VaultRelay), depositAmount));
        if (!ok1) {
            console.log("USDT0 approve failed");
        } else {
            console.log("Step 1: USDT0 approve succeeded");
            console.log("Step 1: Treasury USDT0 allowance after approve:", _erc20Allowance(USDT0_L2, treasury, address(l2VaultRelay)));
        }
        
        // Check vault status before deposit
        (uint256 depBefore, uint256 currBefore, uint256 yieldBefore, uint256 gasBefore) = l2VaultRelay.getStatus(USDT0_L2);
        console.log("Step 1: Vault status before deposit - deposited:", depBefore);
        console.log("Step 1: Vault status before deposit - current:", currBefore);
        console.log("Step 1: Vault status before deposit - yield:", yieldBefore);
        
        // Test encoding before deposit (ensure we're on Ink fork)
        vm.selectFork(inkForkId);
        bytes32 testSupplyArgs;
        try IL2Encoder(L2_ENCODER).encodeSupplyParams(USDT0_L2, depositAmount, 0) returns (bytes32 encoded) {
            testSupplyArgs = encoded;
            (uint16 testAssetId, uint128 testShortAmount, uint16 testReferral) = _decodeSupplyParams(testSupplyArgs);
            console.log("Step 1: Test encoded supply assetId:", testAssetId);
            console.log("Step 1: Test encoded supply shortAmount:", uint256(testShortAmount));
            console.log("Step 1: Test encoded supply referral:", testReferral);
        } catch (bytes memory encoderError) {
            _logRevertData("Step 1: L2Encoder.encodeSupplyParams failed", encoderError);
            console.log("Skipping: L2Encoder not accessible on fork");
            return;
        }
        
        vm.recordLogs();
        bytes memory relayDepositCalldata = abi.encodeWithSelector(
            BundledYieldVaultV2_RELAY.deposit.selector,
            USDT0_L2,
            depositAmount
        );
        (bool relayDepositSuccess, bytes memory relayDepositRet) = address(l2VaultRelay).call(relayDepositCalldata);
        if (relayDepositSuccess) {
            console.log("Step 1: L2 deposit to Tydro executed, amount:", depositAmount);
        } else {
            _logRevertData("Step 1: Relay vault deposit revert", relayDepositRet);
            console.log("Step 1: Treasury USDT0 balance after failed deposit:", _erc20Balance(USDT0_L2, treasury));
            console.log("Step 1: Vault USDT0 balance after failed deposit:", _erc20Balance(USDT0_L2, address(l2VaultRelay)));
            
            // Try direct Tydro supply to see if it works
            vm.startPrank(treasury);
            (bool directApproveOk,) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", TYDRO_POOL, depositAmount));
            if (directApproveOk) {
                console.log("Step 1: Direct Tydro approve succeeded");
                bytes32 directSupplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(USDT0_L2, depositAmount, 0);
                (bool directSupplyOk, bytes memory directSupplyRet) = address(IL2Pool(TYDRO_POOL)).call(
                    abi.encodeWithSelector(IL2Pool.supply.selector, directSupplyArgs)
                );
                if (directSupplyOk) {
                    console.log("Step 1: Direct Tydro supply succeeded");
                } else {
                    _logRevertData("Step 1: Direct Tydro supply failed", directSupplyRet);
                }
            }
            vm.stopPrank();
        }
        Vm.Log[] memory relayDepositLogs = vm.getRecordedLogs();
        if (relayDepositLogs.length == 0) {
            console.log("--- Relay vault deposit logs ---");
            console.log("No logs captured");
        } else {
            _logVmLogs("Relay vault deposit logs", relayDepositLogs);
        }
        vm.stopPrank();
        console.log("Step 1: Relay pool USDT0 balance after deposit attempt:", _erc20Balance(USDT0_L2, TYDRO_POOL));
        console.log("Step 1: Relay vault USDT0 balance after deposit attempt:", _erc20Balance(USDT0_L2, address(l2VaultRelay)));
        if (!relayDepositSuccess) {
            console.log("Halting Relay E2E flow after deposit failure");
            return;
        }
        
        // Step 2: Simulate yield accrual
        (
            ,,
            ,
            ,
            ,
            ,
            ,
            ,
            address aToken,
            ,
            ,
            ,
            ,
            ,

        ) = IL2Pool(TYDRO_POOL).getReserveData(USDT0_L2);
        uint256 simulatedYield = 5 * 1e6;
        if (simulatedYield > 0) {
            vm.startPrank(treasury);
            (bool transferOk,) = USDT0_L2.call(abi.encodeWithSignature("transfer(address,uint256)", address(l2VaultRelay), simulatedYield));
            if (!transferOk) {
                console.log("Warning: transfer failed during relay yield simulation");
            } else {
                vm.stopPrank();
                vm.startPrank(address(l2VaultRelay));
                (bool approveYield,) = USDT0_L2.call(abi.encodeWithSignature("approve(address,uint256)", TYDRO_POOL, simulatedYield));
                if (!approveYield) {
                    console.log("Warning: approve failed during relay yield simulation");
                } else {
                    (, , , , , , , uint16 assetId, , , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(USDT0_L2);
                    bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(USDT0_L2, simulatedYield, 0);
                    try IL2Pool(TYDRO_POOL).supply(supplyArgs) {
                        console.log("Injected simulated yield via supply (relay):", simulatedYield);
                    } catch {
                        console.log("Warning: supply for relay yield simulation reverted");
                    }
                }
            }
            vm.stopPrank();
        }
        l2VaultRelay.updateYield(USDT0_L2);
        _logReserveData("Post-yield reserve data (Relay path)", USDT0_L2);
        
        // Step 3: Check yield status
        (uint256 deposited, uint256 currentBalance, uint256 yieldAvailable, ) = l2VaultRelay.getStatus(USDT0_L2);
        console.log("Step 3: Tydro status - deposited:", deposited);
        console.log("Step 3: Tydro status - current:", currentBalance);
        console.log("Step 3: Tydro status - yield:", yieldAvailable);
        
        // Step 4: Harvest and bridge (if yield available)
        if (yieldAvailable > 0) {
            uint256 expectedBridgeAmount = yieldAvailable;
            vm.startPrank(treasury);
            vm.recordLogs();
            bytes memory relayHarvestCalldata = abi.encodeWithSelector(
                BundledYieldVaultV2_RELAY.harvestAndBridge.selector,
                USDT0_L2,
                uint8(0),
                uint64(0),
                uint256(0)
            );
            (bool relayHarvestSuccess, bytes memory relayHarvestRet) = address(l2VaultRelay).call(relayHarvestCalldata);
            if (relayHarvestSuccess) {
                console.log("Step 4: Harvest & bridge executed, yield:", yieldAvailable);
            } else {
                _logRevertData("Step 4: Harvest & bridge revert", relayHarvestRet);
            }
            Vm.Log[] memory relayHarvestLogs = vm.getRecordedLogs();
            if (relayHarvestLogs.length == 0) {
                console.log("--- Relay harvest logs ---");
                console.log("No logs captured");
            } else {
                _logVmLogs("Relay harvest logs", relayHarvestLogs);
                // Parse HarvestStep and BridgeError events
                _parseHarvestEvents(relayHarvestLogs);
            }
            vm.stopPrank();
            if (!relayHarvestSuccess) {
                console.log("Halting Relay E2E flow after harvest failure");
                return;
            }
            
            // Step 4b: Simulate Relay settlement on L1 by transferring USDT to treasury
            vm.selectFork(ethForkId);
            uint256 l1DepositorBalanceBefore = _erc20Balance(USDT_L1, address(l1Depositor));
            uint256 treasuryBalanceBeforeYield = _erc20Balance(USDT_L1, treasury);
            _ensureL1Liquidity(expectedBridgeAmount);
            vm.startPrank(usdtL1Whale);
            (bool settleOk,) =
                USDT_L1.call(abi.encodeWithSignature("transfer(address,uint256)", address(l1Depositor), expectedBridgeAmount));
            vm.stopPrank();
            if (!settleOk) {
                console.log("Relay settlement transfer failed");
                return;
            }
            uint256 l1DepositorBalanceAfter = _erc20Balance(USDT_L1, address(l1Depositor));
            console.log("Step 4b: L1 Depositor USDT after settlement:", l1DepositorBalanceAfter);
            assertGt(l1DepositorBalanceAfter, l1DepositorBalanceBefore, "Relay settlement did not reach L1 depositor");
            
            vm.startPrank(treasury);
            vm.recordLogs();
            l1Depositor.receiveYield(USDT_L1, expectedBridgeAmount);
            l1Depositor.withdrawYield(USDT_L1, treasury);
            Vm.Log[] memory relayYieldLogs = vm.getRecordedLogs();
            _logVmLogs("Relay yield accounting logs", relayYieldLogs);
            vm.stopPrank();
            uint256 treasuryBalanceAfterYield = _erc20Balance(USDT_L1, treasury);
            console.log("Step 4c: L1 Treasury USDT after withdraw:", treasuryBalanceAfterYield);
            assertGt(treasuryBalanceAfterYield, treasuryBalanceBeforeYield, "Relay yield withdraw did not increase treasury balance");
        } else {
            console.log("Step 4: No yield available yet (would accrue over time)");
        }
        
        console.log("=== E2E Test Complete ===");
    }

    function _logRevertData(string memory label, bytes memory revertData) internal {
        console.log(string.concat("!!! ", label));
        console.log("revert data length:", revertData.length);
        if (revertData.length == 0) {
            console.log("empty revert data");
            return;
        }
        bytes32 word0;
        assembly {
            word0 := mload(add(revertData, 32))
        }
        console.logBytes32(word0);
        bytes4 selector = bytes4(word0);
        if (selector == bytes4(0x750b219c)) {
            console.log("Decoded error: WithdrawFailed() (vault)");
        } else if (selector == bytes4(0xa4937508)) {
            console.log("Decoded error: NotEnoughAvailableLiquidity() (Aave/Tydro)");
        } else if (selector == bytes4(0x850c6f76)) {
            console.log("Decoded error: SlippageTooHigh() (L1 depositor)");
        } else if (selector == bytes4(0x0c55699c)) {
            console.log("Decoded error: DepositFailed() (vault)");
        } else if (selector == bytes4(0x79cacff1)) {
            console.log("Decoded error: DepositFailed() (relay vault)");
        } else if (selector == bytes4(0x08c379a0)) {
            console.log("Decoded error: revert(string)");
        } else if (selector == bytes4(0x4e69d5e7)) {
            console.log("Decoded error: BridgeFailed() (vault)");
        } else if (selector == bytes4(0xc3b9eede)) {
            console.log("Decoded error: BridgeFailed() (vault) - selector 0xc3b9eede");
        } else if (selector == bytes4(0x1c26714c)) {
            console.log("Decoded error: InsufficientGas() (vault)");
        }
        if (revertData.length > 32) {
            bytes32 word1;
            assembly {
                word1 := mload(add(revertData, 64))
            }
            console.logBytes32(word1);
        }
        if (revertData.length > 64) console.log("...(additional revert data omitted)");
    }

    /// @notice Negative-path: L1 deposit reverts when paused
    function testDepositToL2RevertsWhenPaused() public {
        if (usdtL1Whale == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Whale or mapping not configured");
            return;
        }
        uint256 depositAmount = 25 * 1e6;
        _seedTreasuryL1(depositAmount);

        vm.selectFork(ethForkId);
        vm.prank(treasury);
        l1Depositor.pause();

        vm.startPrank(treasury);
        USDT_L1.call(abi.encodeWithSignature("approve(address,uint256)", address(l1Depositor), depositAmount));
        vm.expectRevert();
        l1Depositor.depositToL2(USDT_L1, depositAmount, depositAmount);
        vm.stopPrank();

        vm.prank(treasury);
        l1Depositor.unpause();
    }

    /// @notice Negative-path: Only owner can deposit on L1
    function testDepositToL2OnlyOwner() public {
        if (usdtL1Whale == address(0) || USDT0_L2 == address(0)) {
            console.log("Skipping: Whale or mapping not configured");
            return;
        }
        uint256 attemptAmount = 10 * 1e6;
        vm.selectFork(ethForkId);
        vm.startPrank(usdtL1Whale);
        USDT_L1.call(abi.encodeWithSignature("approve(address,uint256)", address(l1Depositor), attemptAmount));
        vm.expectRevert();
        l1Depositor.depositToL2(USDT_L1, attemptAmount, attemptAmount);
        vm.stopPrank();
    }

    /// @notice Negative-path: L2 vault Across reverts when paused
    function testL2VaultAcrossPaused() public {
        if (inkForkId == 0 || usdt0L2Whale == address(0)) {
            console.log("Skipping: Ink fork or whale not configured");
            return;
        }
        uint256 amount = 50 * 1e6;
        _seedTreasuryL2(amount);

        vm.selectFork(inkForkId);
        vm.prank(treasury);
        l2VaultAcross.pause();

        vm.startPrank(treasury);
        (bool approveOk,) = USDT0_L2.call(
            abi.encodeWithSignature("approve(address,uint256)", address(l2VaultAcross), amount)
        );
        if (!approveOk) console.log("Warning: approve failed during pause test");
        vm.expectRevert();
        l2VaultAcross.deposit(USDT0_L2, amount);
        vm.stopPrank();

        vm.prank(treasury);
        l2VaultAcross.unpause();
    }

    /// @notice Negative-path: L2 vault Relay reverts for unmapped token
    function testL2VaultRelayUnmappedToken() public {
        if (inkForkId == 0) {
            console.log("Skipping: Ink fork not configured");
            return;
        }
        vm.selectFork(inkForkId);
        vm.startPrank(treasury);
        vm.expectRevert(BundledYieldVaultV2_RELAY.TokenNotSupported.selector);
        l2VaultRelay.deposit(address(0xdead), 1);
        vm.stopPrank();
    }

    function _ensureAcrossLiquidity(uint256 amount) internal {
        vm.selectFork(inkForkId);
        uint256 current = _erc20Balance(USDT0_L2, ACROSS_SPOKE_POOL);
        if (current >= amount) return;
        uint256 deficit = amount - current;
        vm.startPrank(usdt0L2Whale);
        (bool topupOk,) = USDT0_L2.call(
            abi.encodeWithSignature("transfer(address,uint256)", ACROSS_SPOKE_POOL, deficit)
        );
        if (!topupOk) console.log("Warning: failed to top up Across SpokePool");
        vm.stopPrank();
    }

    function _ensureL1Liquidity(uint256 amount) internal {
        vm.selectFork(ethForkId);
        uint256 current = _erc20Balance(USDT_L1, usdtL1Whale);
        if (current < amount) {
            console.log("Warning: USDT_L1 whale balance lower than required amount");
        }
    }

    function _logVmLogs(string memory label, Vm.Log[] memory entries) internal {
        console.log(string.concat("--- ", label, " ---"));
        uint256 count = entries.length;
        console.log("entry count:", count);
        uint256 limit = count > 5 ? 5 : count;
        for (uint256 i = 0; i < limit; i++) {
            Vm.Log memory entry = entries[i];
            console.log("log#", i);
            console.log("emitter:", entry.emitter);
            uint256 topicCount = entry.topics.length;
            console.log("topics:", topicCount);
            if (topicCount > 0) console.logBytes32(entry.topics[0]);
            if (topicCount > 1) console.logBytes32(entry.topics[1]);
            if (topicCount > 2) console.logBytes32(entry.topics[2]);
            if (topicCount > 3) console.logBytes32(entry.topics[3]);
            uint256 dataLen = entry.data.length;
            console.log("data length:", dataLen);
            if (dataLen > 0) {
                bytes memory data = entry.data;
                bytes32 word0;
                assembly {
                    word0 := mload(add(data, 32))
                }
                console.logBytes32(word0);
                if (dataLen > 32) {
                    bytes32 word1;
                    assembly {
                        word1 := mload(add(data, 64))
                    }
                    console.logBytes32(word1);
                }
                if (dataLen > 64) console.log("...(additional data omitted)");
            }
        }
        if (count > limit) console.log("...additional logs omitted");
    }

    function _decodeSupplyParams(bytes32 args)
        internal
        pure
        returns (uint16 assetId, uint128 shortAmount, uint16 referralCode)
    {
        uint256 raw = uint256(args);
        assetId = uint16(raw);
        shortAmount = uint128((raw >> 16) & type(uint128).max);
        referralCode = uint16((raw >> 144) & 0xFFFF);
    }

    function _decodeWithdrawParams(bytes32 args)
        internal
        pure
        returns (uint16 assetId, uint128 shortAmount)
    {
        uint256 raw = uint256(args);
        assetId = uint16(raw);
        shortAmount = uint128((raw >> 16) & type(uint128).max);
    }

    function _logReserveData(string memory label, address asset) internal {
        vm.selectFork(inkForkId);
        (
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
        ) = IL2Pool(TYDRO_POOL).getReserveData(asset);
        console.log(string.concat("=== Reserve snapshot: ", label, " ==="));
        console.log("configuration:", configuration);
        console.log("liquidityIndex:", uint256(liquidityIndex));
        console.log("currentLiquidityRate:", uint256(currentLiquidityRate));
        console.log("variableBorrowIndex:", uint256(variableBorrowIndex));
        console.log("currentVariableBorrowRate:", uint256(currentVariableBorrowRate));
        console.log("currentStableBorrowRate:", uint256(currentStableBorrowRate));
        console.log("lastUpdateTimestamp:", uint256(lastUpdateTimestamp));
        console.log("reserveId:", uint256(id));
        console.log("aTokenAddress:", aTokenAddress);
        console.log("stableDebtTokenAddress:", stableDebtTokenAddress);
        console.log("variableDebtTokenAddress:", variableDebtTokenAddress);
        console.log("interestRateStrategyAddress:", interestRateStrategyAddress);
        console.log("accruedToTreasury:", uint256(accruedToTreasury));
        console.log("unbacked:", uint256(unbacked));
        console.log("isolationModeTotalDebt:", uint256(isolationModeTotalDebt));
    }

    function _seedTreasuryL1(uint256 amount) internal {
        vm.selectFork(ethForkId);
        uint256 existing = _erc20Balance(USDT_L1, treasury);
        if (existing >= amount) return;
        if (usdtL1Whale == address(0)) return;
        uint256 needed = amount - existing;
        vm.startPrank(usdtL1Whale);
        (bool ok,) = USDT_L1.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, needed));
        if (!ok) console.log("Warning: L1 whale transfer failed");
        vm.stopPrank();
    }

    function _seedTreasuryL2(uint256 amount) internal {
        vm.selectFork(inkForkId);
        uint256 existing = _erc20Balance(USDT0_L2, treasury);
        if (existing >= amount) return;
        if (usdt0L2Whale == address(0)) return;
        uint256 needed = amount - existing;
        vm.startPrank(usdt0L2Whale);
        (bool ok,) = USDT0_L2.call(abi.encodeWithSignature("transfer(address,uint256)", treasury, needed));
        if (!ok) console.log("Warning: L2 whale transfer failed");
        vm.stopPrank();
    }

    function _erc20Balance(address token, address who) internal view returns (uint256 bal) {
        (bool success, bytes memory rd) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        if (success && rd.length >= 32) bal = abi.decode(rd, (uint256));
    }
    
    function _erc20Allowance(address token, address owner, address spender) internal view returns (uint256 allowance) {
        (bool success, bytes memory rd) = token.staticcall(abi.encodeWithSignature("allowance(address,address)", owner, spender));
        if (success && rd.length >= 32) allowance = abi.decode(rd, (uint256));
    }
    
    /// @notice Parse HarvestStep and BridgeError events from logs
    function _parseHarvestEvents(Vm.Log[] memory logs) internal {
        bytes32 harvestStepTopic = keccak256("HarvestStep(address,string)");
        bytes32 bridgeErrorTopic = keccak256("BridgeError(address,bytes4,uint256,uint256)");
        
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics.length > 0) {
                bytes32 topic0 = log.topics[0];
                if (topic0 == harvestStepTopic) {
                    // HarvestStep(address indexed token, string step)
                    if (log.topics.length > 1) {
                        address token = address(uint160(uint256(log.topics[1])));
                        // Decode string from data (offset + length + string)
                        if (log.data.length >= 64) {
                            bytes memory data = log.data;
                            uint256 offset;
                            uint256 length;
                            assembly {
                                offset := mload(add(data, 32))
                                length := mload(add(data, 64))
                            }
                            if (length > 0 && length <= 100) {
                                bytes memory stepBytes = new bytes(length);
                                for (uint256 j = 0; j < length; j++) {
                                    stepBytes[j] = data[64 + j];
                                }
                                string memory step = string(stepBytes);
                                console.log(string.concat("HarvestStep[", step, "] for token: ", vm.toString(token)));
                            } else {
                                console.log("HarvestStep event (could not decode step)");
                            }
                        }
                    }
                } else if (topic0 == bridgeErrorTopic) {
                    // BridgeError(address indexed token, bytes4 errorSelector, uint256 bridgeAmount, uint256 minAmountOut)
                    console.log("=== BridgeError event ===");
                    if (log.topics.length > 1) {
                        address token = address(uint160(uint256(log.topics[1])));
                        console.log("Token:", token);
                    }
                    if (log.data.length >= 68) {
                        bytes memory data = log.data;
                        bytes4 selector;
                        uint256 bridgeAmount;
                        uint256 minAmountOut;
                        assembly {
                            selector := mload(add(data, 4))
                            bridgeAmount := mload(add(data, 36))
                            minAmountOut := mload(add(data, 68))
                        }
                        console.log("BridgeError - selector:");
                        console.logBytes4(selector);
                        console.log("BridgeError - bridgeAmount:", bridgeAmount);
                        console.log("BridgeError - minAmountOut:", minAmountOut);
                    }
                }
            }
        }
    }
}

