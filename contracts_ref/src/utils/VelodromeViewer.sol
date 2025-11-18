// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IVeloRouter, IVeloPair, IVeloGauge, IVeloVoter} from "../interfaces/IVelodrome.sol";

/// @title VelodromeViewer
/// @notice View-only utility to check LP positions, rewards, and balances
/// @dev No state changes - just read data for your EOA
contract VelodromeViewer {
    address public immutable VELO_ROUTER;
    address public immutable VELO_VOTER;
    
    struct LPInfo {
        address pair;
        address gauge;
        uint256 lpBalance;
        uint256 stakedBalance;
        uint256 earnedRewards;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalSupply;
    }
    
    constructor(address _veloRouter, address _veloVoter) {
        VELO_ROUTER = _veloRouter;
        VELO_VOTER = _veloVoter;
    }
    
    /// @notice Get full LP info for a user
    function getLPInfo(
        address user,
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (LPInfo memory info) {
        info.pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
        if (info.pair == address(0)) return info;
        
        info.gauge = IVeloVoter(VELO_VOTER).gauges(info.pair);
        info.lpBalance = IVeloPair(info.pair).balanceOf(user);
        
        if (info.gauge != address(0)) {
            info.stakedBalance = IVeloGauge(info.gauge).balanceOf(user);
            info.earnedRewards = IVeloGauge(info.gauge).earned(user);
        }
        
        (info.reserve0, info.reserve1, ) = IVeloPair(info.pair).getReserves();
        info.totalSupply = IVeloPair(info.pair).totalSupply();
    }
    
    /// @notice Get all LP positions for a user across multiple pairs
    function getMultipleLPInfo(
        address user,
        address[] calldata tokenAs,
        address[] calldata tokenBs,
        bool[] calldata stables
    ) external view returns (LPInfo[] memory infos) {
        uint256 len = tokenAs.length;
        require(len == tokenBs.length && len == stables.length, "Length mismatch");
        
        infos = new LPInfo[](len);
        for (uint256 i = 0; i < len; i++) {
            infos[i] = this.getLPInfo(user, tokenAs[i], tokenBs[i], stables[i]);
        }
    }
    
    /// @notice Get pair address
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address) {
        return IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
    }
    
    /// @notice Get gauge address for a pair
    function getGauge(address pair) external view returns (address) {
        return IVeloVoter(VELO_VOTER).gauges(pair);
    }
}

