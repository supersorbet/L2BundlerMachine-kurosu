// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IVeloRouter, IVeloPair} from "../interfaces/IVelodrome.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title VelodromeStrategy
/// @notice Yield strategy for Velodrome liquidity provision
/// @dev Strategy ID: 2
/// @dev auxData format: abi.encode(tokenB, stable) where stable is bool
contract VelodromeStrategy is IYieldStrategy {
    using SafeTransferLib for address;
    
    address public immutable VELO_ROUTER;
    
    error DepositFailed();
    error WithdrawFailed();
    error InvalidAuxData();
    
    constructor(address _veloRouter) {
        VELO_ROUTER = _veloRouter;
    }
    
    function strategyId() external pure returns (uint8) {
        return 2;
    }
    
    function strategyName() external pure returns (string memory) {
        return "Velodrome LP";
    }
    
    function deposit(address token, uint256 amount, bytes calldata auxData) external returns (uint256 shares) {
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        
        // For stablecoin pairs, we need equal amounts of both tokens
        // This is a simplified version - in production, you'd handle price ratios
        uint256 amountB = amount; // Assuming 1:1 for stablecoins
        SafeTransferLib.safeApprove(token, VELO_ROUTER, amount);
        SafeTransferLib.safeApprove(tokenB, VELO_ROUTER, amountB);
        
        try IVeloRouter(VELO_ROUTER).addLiquidity(
            token,
            tokenB,
            stable,
            amount,
            amountB,
            0, // amountAMin
            0, // amountBMin
            msg.sender,
            block.timestamp
        ) returns (uint256, uint256, uint256 liquidity) {
            return liquidity; // Shares = LP tokens
        } catch {
            revert DepositFailed();
        }
    }
    
    function withdraw(address token, uint256 shares, bytes calldata auxData) external returns (uint256 amount) {
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) revert WithdrawFailed();
        SafeTransferLib.safeApprove(pair, VELO_ROUTER, shares);
        try IVeloRouter(VELO_ROUTER).removeLiquidity(
            token,
            tokenB,
            stable,
            shares,
            0, // amountAMin
            0, // amountBMin
            msg.sender,
            block.timestamp
        ) returns (uint256 amountA, uint256) {
            return amountA; // Return tokenA amount
        } catch {
            revert WithdrawFailed();
        }
    }
    
    function getBalance(address token, bytes calldata auxData) external view returns (uint256 balance) {
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) return 0;
        
        // Get LP token balance
        (bool success, bytes memory data) = pair.staticcall(
            abi.encodeWithSignature("balanceOf(address)", msg.sender)
        );
        if (!success || data.length < 32) return 0;
        
        uint256 lpBalance = abi.decode(data, (uint256));
        if (lpBalance == 0) return 0;
        
        // Get total supply and reserves to calculate token amount
        // Simplified: assume 1 LP token ≈ 2 tokens (for stable pairs)
        // In production, calculate based on actual reserves
        return lpBalance; // Simplified - should calculate based on reserves
    }
    
    function getAvailableYield(address token, bytes calldata auxData) external view returns (uint256 yield) {
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) return 0;
        try IVeloPair(pair).claimableFeesToken0() returns (uint256 fees) {
            return fees;
        } catch {
            return 0;
        }
    }
    
    function harvest(address token, bytes calldata auxData) external returns (uint256 harvested) {
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) return 0;
        try IVeloPair(pair).claimFees() returns (uint256 fee0, uint256) {
            return fee0; // Return token0 fees
        } catch {
            return 0;
        }
    }
    
    function getAPY(address token, bytes calldata auxData) external view returns (uint256 apyBps) {
        // Velodrome APY is typically much higher than Tydro
        // For stablecoins, can be 20-50%+ APY
        // This would need to be calculated from:
        // 1. Trading volume
        // 2. Fee rate (typically 0.01% or 0.05%)
        // 3. VELO emissions
        
        // For now, return a high default (can be updated with oracle)
        // In production, integrate with Velodrome's analytics or calculate from reserves
        return 3000; // 30% APY default (conservative estimate for high-yield pools)
    }
    
    function supportsToken(address token, bytes calldata auxData) external view returns (bool supported) {
        if (auxData.length < 64) return false;
        (address tokenB, bool stable) = abi.decode(auxData, (address, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        return pair != address(0);
    }
}

