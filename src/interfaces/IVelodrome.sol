// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Velodrome Pair interface
interface IVeloPair {
    function claimFees() external returns (uint256, uint256);
    function claimableFeesToken0() external view returns (uint256);
    function claimableFeesToken1() external view returns (uint256);
}

/// @notice Velodrome Router interface
interface IVeloRouter {
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
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);
}

