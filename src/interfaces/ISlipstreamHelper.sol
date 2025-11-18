// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISlipstreamPositionNFT} from "./ISlipstream.sol";

/// @notice Interface for SlipstreamHelper contract
interface ISlipstreamHelper {
    function setVault(address _vault) external;
    function setLeafGauge(address tokenA, address tokenB, uint24 fee, address gauge) external;
    function createPosition(ISlipstreamPositionNFT.MintParams calldata params, bool stakeInGauge) external returns (uint256 tokenId);
    function zapIntoPosition(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, int24 tickLower, int24 tickUpper, uint256 minAmount0, uint256 minAmount1, bool stakeInGauge) external returns (uint256 tokenId);
    function increaseLiquidity(uint256 tokenId, ISlipstreamPositionNFT.IncreaseLiquidityParams calldata params) external returns (uint256 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(uint256 tokenId, ISlipstreamPositionNFT.DecreaseLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1);
    function collectFees(uint256 tokenId, address recipient) external returns (uint256 amount0, uint256 amount1);
    function harvestRewards(bytes32 positionHash) external returns (uint256 rewards);
    function stakePosition(uint256 tokenId, bytes32 positionHash) external;
    function unstakePosition(uint256 tokenId, bytes32 positionHash) external;
    function transferPosition(uint256 tokenId, address to) external;
    function getPositionTokenIds(bytes32 positionHash) external view returns (uint256[] memory);
    function getStakedTokenIds(bytes32 positionHash) external view returns (uint256[] memory);
    function getEarnedRewards(bytes32 positionHash) external view returns (uint256 rewards);
    function getPosition(uint256 tokenId) external view returns (address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity);
    function positionHash(address tokenA, address tokenB, uint24 fee) external pure returns (bytes32);
}

