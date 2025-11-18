// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVelodromeHelper {
    function setVault(address _vault) external;
    function setVeloVoter(address _veloVoter) external;
    function createLP(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bool stable, bool stakeInGauge) external returns (uint256 liquidity);
    function zapIntoLP(address tokenIn, address tokenOut, uint256 amountIn, bool stable, bool stakeInGauge, uint256 minLiquidity) external returns (uint256 liquidity);
    function harvestRewards(bytes32 pairHash) external returns (uint256 harvested);
    function harvestFees(address tokenA, address tokenB, bool stable) external returns (uint256 fee0, uint256 fee1);
    function getGauge(address tokenA, address tokenB, bool stable) external view returns (address gauge);
    function transferLP(address pair, address to, uint256 amount) external;
    function getLPBalance(bytes32 pairHash) external view returns (uint256 balance);
    function getStakedLPBalance(bytes32 pairHash) external view returns (uint256 staked);
    function getTotalLPBalance(bytes32 pairHash) external view returns (uint256 total);
    function unstakeLP(bytes32 pairHash, uint256 amount) external returns (uint256 unstaked);
}

