// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IVeloRouter, IVeloPair, IVeloGauge, IVeloVoter} from "../interfaces/IVelodrome.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title VelodromeLPStrategy
/// @notice Enhanced Velodrome LP strategy with gauge staking for VELO rewards
/// @dev Strategy ID: 2
/// @dev auxData format: abi.encode(tokenB, stable, stakeInGauge) where stakeInGauge is bool
contract VelodromeLPStrategy is IYieldStrategy {
    using SafeTransferLib for address;
    
    address public immutable VELO_ROUTER;
    address public immutable VELO_VOTER;
    address public immutable VELO_TOKEN;
    
    error DepositFailed();
    error WithdrawFailed();
    error InvalidAuxData();
    error GaugeNotFound();
    
    constructor(address _veloRouter, address _veloVoter, address _veloToken) {
        VELO_ROUTER = _veloRouter;
        VELO_VOTER = _veloVoter;
        VELO_TOKEN = _veloToken;
    }
    
    function strategyId() external pure returns (uint8) {
        return 2;
    }
    
    function deposit(address token, uint256 amount, bytes calldata auxData) external returns (uint256 shares) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        
        uint256 amountB = amount;
        SafeTransferLib.safeApprove(token, VELO_ROUTER, amount);
        SafeTransferLib.safeApprove(tokenB, VELO_ROUTER, amountB);
        
        (uint256 usedA, uint256 usedB, uint256 liquidity) = IVeloRouter(VELO_ROUTER).addLiquidity(
            token,
            tokenB,
            stable,
            amount,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) revert DepositFailed();
        
        if (stakeInGauge) {
            address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
            if (gauge == address(0)) revert GaugeNotFound();
            
            SafeTransferLib.safeApprove(pair, gauge, liquidity);
            IVeloGauge(gauge).deposit(liquidity, msg.sender);
        }
        
        return liquidity;
    }
    
    function withdraw(address token, uint256 shares, bytes calldata auxData) external returns (uint256 amount) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) revert WithdrawFailed();
        
        if (stakeInGauge) {
            address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
            if (gauge != address(0)) {
                IVeloGauge(gauge).withdraw(shares);
            }
        }
        
        SafeTransferLib.safeApprove(pair, VELO_ROUTER, shares);
        (uint256 amountA, ) = IVeloRouter(VELO_ROUTER).removeLiquidity(
            token,
            tokenB,
            stable,
            shares,
            0,
            0,
            msg.sender,
            block.timestamp
        );
        
        return amountA;
    }
    
    function harvest(address token, bytes calldata auxData) external returns (uint256 harvested) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        
        if (!stakeInGauge) {
            address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
            if (pair == address(0)) return 0;
            (uint256 fee0, ) = IVeloPair(pair).claimFees();
            return fee0;
        }
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
        if (gauge == address(0)) return 0;
        
        IVeloGauge(gauge).getReward(msg.sender);
        
        uint256 veloEarned = IVeloGauge(gauge).earned(msg.sender);
        return veloEarned;
    }
    
    function getAPY(address token, bytes calldata auxData) external view returns (uint256 apyBps) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) return 0;
        
        uint256 baseAPY = 2000;
        
        if (stakeInGauge) {
            address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
            if (gauge != address(0)) {
                baseAPY += 1000;
            }
        }
        
        return baseAPY;
    }
    
    function getBalance(address token, bytes calldata auxData) external view returns (uint256 balance) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        if (pair == address(0)) return 0;
        
        if (stakeInGauge) {
            address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
            if (gauge == address(0)) return 0;
            return IVeloGauge(gauge).balanceOf(msg.sender);
        }
        
        (bool success, bytes memory data) = pair.staticcall(
            abi.encodeWithSignature("balanceOf(address)", msg.sender)
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }
    
    function getAvailableYield(address token, bytes calldata auxData) external view returns (uint256 yield) {
        (address tokenB, bool stable, bool stakeInGauge) = abi.decode(auxData, (address, bool, bool));
        
        if (!stakeInGauge) {
            address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
            if (pair == address(0)) return 0;
            try IVeloPair(pair).claimableFeesToken0() returns (uint256 fees) {
                return fees;
            } catch {
                return 0;
            }
        }
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        address gauge = IVeloVoter(VELO_VOTER).gauges(pair);
        if (gauge == address(0)) return 0;
        
        return IVeloGauge(gauge).earned(msg.sender);
    }
    
    function supportsToken(address token, bytes calldata auxData) external view returns (bool supported) {
        if (auxData.length < 96) return false;
        (address tokenB, bool stable,) = abi.decode(auxData, (address, bool, bool));
        address pair = IVeloRouter(VELO_ROUTER).pairFor(token, tokenB, stable);
        return pair != address(0);
    }
    
    function strategyName() external pure returns (string memory) {
        return "Velodrome LP";
    }
}
