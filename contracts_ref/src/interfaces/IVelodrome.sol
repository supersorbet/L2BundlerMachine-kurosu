// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Velodrome Pair interface
interface IVeloPair {
    function claimFees() external returns (uint256, uint256);
    function claimableFeesToken0() external view returns (uint256);
    function claimableFeesToken1() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256);
}

/// @notice Velodrome Router interface
interface IVeloRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
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
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);
}

/// @notice Velodrome Gauge interface (for staking LP tokens and earning VELO)
interface IVeloGauge {
    function deposit(uint256 amount, address recipient) external;
    function withdraw(uint256 amount) external returns (uint256);
    function getReward(address account) external;
    function earned(address account) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Velodrome VotingEscrow interface (for staking VELO tokens)
interface IVotingEscrow {
    function createLock(uint256 value, uint256 unlockTime) external returns (uint256);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function increaseUnlockTime(uint256 tokenId, uint256 unlockTime) external;
    function withdraw(uint256 tokenId) external;
    function balanceOfNFT(uint256 tokenId) external view returns (uint256);
    function locked(uint256 tokenId) external view returns (int128 amount, uint256 end);
}

/// @notice Velodrome Voter interface (for finding gauges)
interface IVeloVoter {
    function gauges(address pair) external view returns (address);
    function isGauge(address gauge) external view returns (bool);
}

