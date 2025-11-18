// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {L1DepositorV2_PRODUCTION} from "../src/L1DepositorV2_PRODUCTION.sol";
import {BundledYieldVaultV2_PRODUCTION} from "../src/BundledYieldVaultV2_PRODUCTION.sol";

/**
 * @title YieldAggregatorTest
 * @notice Basic test suite for L1-L2 yield aggregator contracts
 * @dev Note: Full testing requires forking mainnet and Ink L2
 */
contract YieldAggregatorTest is Test {
    L1DepositorV2_PRODUCTION public l1Depositor;
    BundledYieldVaultV2_PRODUCTION public l2Vault;
    
    address public constant HUB_POOL = address(0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5);
    address public constant TYDRO_POOL = address(0x1234); // Mock
    address public constant L2_ENCODER = address(0x4321); // Mock encoder
    address public constant ACROSS_SPOKE_POOL = address(0x5678); // Mock
    address public constant VELO_ROUTER = address(0x9999); // Mock
    address public constant SLIPSTREAM_POSITION_NFT = address(0xAAAA); // Mock
    
    address public deployer;
    address public user;
    
    function setUp() public {
        deployer = address(this);
        user = address(0x999);
        
        // Deploy L2 vault first
        l2Vault = new BundledYieldVaultV2_PRODUCTION(
            TYDRO_POOL,
            L2_ENCODER,
            ACROSS_SPOKE_POOL,
            address(0x1), // L1 recipient placeholder
            VELO_ROUTER,
            SLIPSTREAM_POSITION_NFT
        );
        
        // Deploy L1 depositor (chain ID 1 for Ethereum mainnet)
        l1Depositor = new L1DepositorV2_PRODUCTION(
            HUB_POOL,
            address(l2Vault),
            1 // destinationChainId for Ink L2 (update with actual chain ID)
        );
    }
    
    function testDeployment() public view {
        assertEq(address(l1Depositor.HUB_POOL()), HUB_POOL);
        assertEq(l1Depositor.l2Vault(), address(l2Vault));
        assertEq(l2Vault.TYDRO_POOL(), TYDRO_POOL);
        assertEq(l2Vault.ACROSS_SPOKE_POOL(), ACROSS_SPOKE_POOL);
    }
    
    function testSetTokenMapping() public {
        address l1Token = address(0xAAA);
        address l2Token = address(0xBBB);
        
        // Set on L1
        l1Depositor.setTokenMapping(l1Token, l2Token);
        assertEq(l1Depositor.tokenMapping(l1Token), l2Token);
        
        // Set on L2
        l2Vault.mapToken(l2Token, l1Token);
        assertEq(l2Vault.tokenMapping(l2Token), l1Token);
    }
    
    function testSetL2Vault() public {
        address newVault = address(0x1234567890123456789012345678901234567890);
        l1Depositor.setL2Vault(newVault);
        assertEq(l1Depositor.l2Vault(), newVault);
    }
    
    function testSetL1Recipient() public {
        address newRecipient = address(0x9876543210987654321098765432109876543210);
        l2Vault.setL1Recipient(newRecipient);
        assertEq(l2Vault.l1Recipient(), newRecipient);
    }
    
    function testPauseUnpause() public {
        // Pause L1
        l1Depositor.pause();
        assertTrue(l1Depositor.paused());
        
        l1Depositor.unpause();
        assertFalse(l1Depositor.paused());
        
        // Pause L2
        l2Vault.pause();
        assertTrue(l2Vault.paused());
        
        l2Vault.unpause();
        assertFalse(l2Vault.paused());
    }
    
    function testSetMaxSlippage() public {
        uint64 newSlippage = 100; // 1%
        l1Depositor.setMaxSlippage(newSlippage);
        assertEq(l1Depositor.maxSlippageBps(), newSlippage);
    }
    
    function testSetMinDeposit() public {
        uint128 newMin = 5000;
        l1Depositor.setMinDepositAmount(newMin);
        assertEq(l1Depositor.minDepositAmount(), newMin);
    }
    
    function testSetMinGasBalance() public {
        uint128 newMin = uint128(0.1 ether);
        l2Vault.setMinGasBal(newMin);
        assertEq(l2Vault.minGasBalance(), newMin);
    }
    
    function testRefillGas() public {
        uint256 amount = 0.1 ether;
        vm.deal(user, amount);
        
        vm.prank(user);
        l2Vault.refillGas{value: amount}();
        
        assertEq(address(l2Vault).balance, amount);
    }
    
    function testTokenNotSupported() public {
        address unsupportedToken = address(0x1111111111111111111111111111111111111111);
        
        vm.expectRevert(L1DepositorV2_PRODUCTION.TokenNotSupported.selector);
        l1Depositor.depositToL2(unsupportedToken, 1000, 950);
    }
    
    function testL2VaultNotSet() public {
        // Create new depositor without L2 vault
        L1DepositorV2_PRODUCTION newDepositor = new L1DepositorV2_PRODUCTION(
            HUB_POOL,
            address(0),
            1 // destinationChainId
        );
        
        address token = address(0x2222222222222222222222222222222222222222);
        newDepositor.setTokenMapping(token, address(0x3333333333333333333333333333333333333333));
        
        vm.expectRevert(L1DepositorV2_PRODUCTION.L2VaultNotSet.selector);
        newDepositor.depositToL2(token, 1000, 950);
    }
}

