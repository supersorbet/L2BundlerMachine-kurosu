// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {MockAToken} from "./MockAToken.sol";

/// @title MockTydroPool
/// @notice Mock AAVE V3-style pool that simulates yield over time
contract MockTydroPool is ERC20 {
    using SafeTransferLib for address;

    /// @notice Annual yield rate (in basis points, e.g., 300 = 3% APY)
    uint256 public annualYieldBps = 300;
    
    /// @notice Track deposits per token
    mapping(address => uint256) public deposits;
    
    /// @notice Track last deposit timestamp per token
    mapping(address => uint256) public lastDepositTime;
    
    /// @notice aToken for each underlying token
    mapping(address => address) public aTokens;

    constructor() ERC20("Mock Tydro Pool", "MTYDRO") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @notice Deploy aToken if needed
    function _ensureAToken(address token) internal {
        if (aTokens[token] == address(0)) {
            MockAToken aToken = new MockAToken(token, address(this));
            aTokens[token] = address(aToken);
        }
    }

    /// @notice Deposit tokens (AAVE V3 style)
    function deposit(address token, uint256 amount) external returns (uint256) {
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        _ensureAToken(token);
        deposits[token] += amount;
        lastDepositTime[token] = block.timestamp;
        
        // Mint aTokens 1:1
        MockAToken(aTokens[token]).mint(msg.sender, amount);
        
        return amount; // Return shares (1:1 for simplicity)
    }

    /// @notice Withdraw tokens
    function withdraw(address token, uint256 amount) external returns (uint256) {
        address aToken = aTokens[token];
        require(aToken != address(0), "Token not deployed");
        
        // Get user's aToken balance
        uint256 userATokenBalance = MockAToken(aToken).balanceOf(msg.sender);
        require(userATokenBalance >= amount, "Insufficient aToken balance");
        
        // Calculate current balance with yield
        uint256 currentBalance = _getCurrentBalance(token);
        
        // Burn aTokens
        MockAToken(aToken).burn(msg.sender, amount);
        
        // Calculate actual withdrawal (account for yield accrued)
        uint256 withdrawalAmount = amount;
        if (currentBalance > deposits[token]) {
            // There's yield - user gets proportional amount
            withdrawalAmount = (amount * currentBalance) / deposits[token];
        }
        
        // Transfer tokens
        token.safeTransfer(msg.sender, withdrawalAmount);
        
        // Update deposits
        if (deposits[token] >= amount) {
            deposits[token] -= amount;
        } else {
            deposits[token] = 0;
        }
        
        return amount;
    }

    /// @notice Get current balance with yield accrued
    function _getCurrentBalance(address token) internal view returns (uint256) {
        uint256 principal = deposits[token];
        if (principal == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - lastDepositTime[token];
        if (timeElapsed == 0) return principal;
        
        // Calculate yield: principal * (annualYield / seconds per year) * timeElapsed
        // Simplified: assume 1 second = minimal yield for testing
        uint256 yield = (principal * annualYieldBps * timeElapsed) / (10000 * 365 days);
        
        return principal + yield;
    }

    /// @notice Get reserve data (for aToken address lookup)
    function getReserveData(address asset) external view returns (
        uint256,
        uint128,
        uint128,
        uint128,
        uint128,
        uint128,
        uint40,
        uint16,
        address aTokenAddress,
        address,
        address,
        address,
        uint128,
        uint128,
        uint128
    ) {
        return (
            0, 0, 0, 0, 0, 0, 0, 0,
            aTokens[asset],
            address(0), address(0), address(0),
            0, 0, 0
        );
    }

    /// @notice Balance of underlying in pool (override ERC20, but return deposits)
    function balanceOf(address account) public view override returns (uint256) {
        // For testing, return total deposits for the account's tokens
        // This is a mock - in reality we'd track per-account
        return deposits[account];
    }
}


