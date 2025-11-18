// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IL2Pool} from "../interfaces/IL2Pool.sol";
import {IL2Encoder} from "../interfaces/IL2Encoder.sol";
import {IAToken} from "../interfaces/ITydroAAVE.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title TydroStrategy
/// @notice Yield strategy for Tydro lending 
/// @dev Strategy ID: 1
contract TydroStrategy is IYieldStrategy {
    using SafeTransferLib for address;
    
    address public immutable TYDRO_POOL;
    address public immutable L2_ENCODER;
    
    error DepositFailed();
    error WithdrawFailed();
    error TokenNotSupported();
    
    constructor(address _tydroPool, address _l2Encoder) {
        TYDRO_POOL = _tydroPool;
        L2_ENCODER = _l2Encoder;
    }
    
    function strategyId() external pure returns (uint8) {
        return 1;
    }
    
    function strategyName() external pure returns (string memory) {
        return "Tydro Lending";
    }
    
    function deposit(address token, uint256 amount, bytes calldata) external returns (uint256 shares) {
        uint256 allowance = _getAllowance(token, TYDRO_POOL);
        if (allowance < amount) {
            SafeTransferLib.safeApprove(token, TYDRO_POOL, 0);
            SafeTransferLib.safeApprove(token, TYDRO_POOL, amount);
        }
        
        bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(token, amount, 0);
        try IL2Pool(TYDRO_POOL).supply(supplyArgs) {
           ///Success - shares = amount (1:1 for lending)
            return amount;
        } catch {
            revert DepositFailed();
        }
    }
    
    function withdraw(address token, uint256 shares, bytes calldata) external returns (uint256 amount) {
        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(token, shares);
        try IL2Pool(TYDRO_POOL).withdraw(withdrawArgs) returns (uint256 withdrawn) {
            return withdrawn;
        } catch {
            revert WithdrawFailed();
        }
    }
    
    function getBalance(address token, bytes calldata) external view returns (uint256 balance) {
       ///Get aToken address
        (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
        if (aTokenAddress == address(0)) return 0;
        
       ///Balance = aToken balance (includes accrued interest)
        return IAToken(aTokenAddress).balanceOf(msg.sender);
    }
    
    function getAvailableYield(address token, bytes calldata) external view returns (uint256 yield) {
       ///Get aToken address
        (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
        if (aTokenAddress == address(0)) return 0;
        
        uint256 currentBalance = IAToken(aTokenAddress).balanceOf(msg.sender);
       ///Yield = current balance - principal (principal tracked by allocator)
       ///For now, return 0 as principal is tracked externally
       ///This will be calculated by the allocator
        return 0;
    }
    
    function harvest(address token, bytes calldata) external returns (uint256 harvested) {
       ///For Tydro, yield is automatically accrued in aToken balance
       ///Harvesting means withdrawing the yield portion
       ///This is handled by the allocator which tracks principal
        return 0;
    }
    
    function getAPY(address token, bytes calldata) external view returns (uint256 apyBps) {
       ///Get current liquidity rate from Tydro
        (, , uint128 currentLiquidityRate, , , , , , , , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
        
       ///Convert ray (1e27) to basis points
       ///APY = (rate / 1e27) * 10000
       ///For simplicity, return rate / 1e23 (approximate conversion)
        if (currentLiquidityRate == 0) return 0;
        return uint256(currentLiquidityRate) / 1e23;///Rough conversion
    }
    
    function supportsToken(address token, bytes calldata) external view returns (bool supported) {
       ///Check if token is listed in Tydro
        (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
        return aTokenAddress != address(0);
    }
    
    function _getAllowance(address token, address spender) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("allowance(address,address)", address(this), spender)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }
}

