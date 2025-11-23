// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BundledYieldVaultV2__MULTICALL} from "./BundledYieldVaultV2_PRODUCTION_MULTICALL.sol";
import {IAToken} from "./interfaces/ITydroAAVE.sol";
import {IL2Pool} from "./interfaces/IL2Pool.sol";
import {ISlipstreamHelper} from "./interfaces/ISlipstreamHelper.sol";
import {IVelodromeHelper} from "./interfaces/IVelodromeHelper.sol";

/// @title YieldViewer
/// @notice View-only contract for checking yield vault status manually
/// @dev Can be called from any wallet/contract without owner permissions
/// @dev Perfect for manual checks when not near a computer
/// @author sorbet/pepecoin core
contract YieldViewer {
    
    /// @notice Vault contract address
    address payable public immutable VAULT;
    
    /// @notice Tydro pool address
    address public immutable TYDRO_POOL;
    
    /// @notice Slipstream helper address
    address public immutable SLIPSTREAM_HELPER;
    
    /// @notice Velodrome helper address
    address public immutable VELO_HELPER;
    
    constructor(
        address _vault,
        address _tydroPool,
        address _slipstreamHelper,
        address _veloHelper
    ) {
        VAULT = payable(_vault);
        TYDRO_POOL = _tydroPool;
        SLIPSTREAM_HELPER = _slipstreamHelper;
        VELO_HELPER = _veloHelper;
    }
    
    /// @notice Get comprehensive status for a token
    /// @param token Token address
    /// @return depositedAmount Amount deposited to Tydro
    /// @return currentBalance Current balance in Tydro (includes yield)
    /// @return yieldAvailable Available yield to harvest
    /// @return apyBps Current APY in basis points
    /// @return gasBalance Vault's ETH balance
    /// @return aTokenAddress aToken address for this token
    function getTokenStatus(address token)
        external
        view
        returns (
            uint256 depositedAmount,
            uint256 currentBalance,
            uint256 yieldAvailable,
            uint256 apyBps,
            uint256 gasBalance,
            address aTokenAddress
        )
    {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        
        // Get basic status
        (depositedAmount, currentBalance, yieldAvailable, gasBalance) = vault.getStatus(token);
        
        // Get APY
        apyBps = vault.getCurrentAPY(token);
        
        // Get aToken address
        aTokenAddress = vault.getATokenAddress(token);
    }
    
    /// @notice Get yield available for a token (direct aToken balance check)
    /// @param token Token address
    /// @return yield Available yield amount
    function getYieldAvailable(address token) external view returns (uint256 yield) {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        return vault.getYieldAvailable(token);
    }
    
    /// @notice Get vault health for a token
    /// @param token Token address
    /// @return isHealthy Vault is healthy (not paused, no circuit breaker)
    /// @return hasGas Vault has sufficient gas
    /// @return hasYield Yield is available
    /// @return timeSinceLastUpdate Seconds since last update
    /// @return totalValueLocked Total value locked in Tydro
    function getVaultHealth(address token)
        external
        view
        returns (
            bool isHealthy,
            bool hasGas,
            bool hasYield,
            uint256 timeSinceLastUpdate,
            uint256 totalValueLocked
        )
    {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        return vault.getVaultHealth(token);
    }
    
    /// @notice Get current APY for a token
    /// @param token Token address
    /// @return apyBps APY in basis points (e.g., 500 = 5%)
    function getCurrentAPY(address token) external view returns (uint256 apyBps) {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        return vault.getCurrentAPY(token);
    }
    
    /// @notice Get total value locked across multiple tokens
    /// @param tokens Array of token addresses
    /// @return total Total value locked
    function getTotalValueLocked(address[] calldata tokens)
        external
        view
        returns (uint256 total)
    {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        return vault.getTotalValueLocked(tokens);
    }
    
    /// @notice Check if operation can be performed
    /// @param token Token address
    /// @return canOperate True if operation can be performed
    /// @return reason Reason if operation cannot be performed
    function canPerformOp(address token)
        external
        view
        returns (bool canOperate, string memory reason)
    {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        return vault.canPerformOp(token);
    }
    
    /// @notice Get Slipstream position details
    /// @param tokenId NFT token ID
    /// @return token0 Token0 address
    /// @return token1 Token1 address
    /// @return fee Fee tier
    /// @return tickLower Lower tick
    /// @return tickUpper Upper tick
    /// @return liquidity Current liquidity
    function getSlipstreamPosition(uint256 tokenId)
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        return ISlipstreamHelper(SLIPSTREAM_HELPER).getPosition(tokenId);
    }
    
    /// @notice Get Slipstream position token IDs for a position hash
    /// @param token0 Token0 address
    /// @param token1 Token1 address
    /// @param fee Fee tier
    /// @return tokenIds Array of NFT token IDs
    function getSlipstreamPositionTokenIds(
        address token0,
        address token1,
        uint24 fee
    ) external view returns (uint256[] memory tokenIds) {
        bytes32 positionHash = keccak256(abi.encodePacked(
            token0 < token1 ? token0 : token1,
            token0 < token1 ? token1 : token0,
            fee
        ));
        return ISlipstreamHelper(SLIPSTREAM_HELPER).getPositionTokenIds(positionHash);
    }
    
    /// @notice Get earned rewards for a Slipstream position
    /// @param token0 Token0 address
    /// @param token1 Token1 address
    /// @param fee Fee tier
    /// @return rewards Amount of rewards earned
    function getSlipstreamEarnedRewards(
        address token0,
        address token1,
        uint24 fee
    ) external view returns (uint256 rewards) {
        bytes32 positionHash = keccak256(abi.encodePacked(
            token0 < token1 ? token0 : token1,
            token0 < token1 ? token1 : token0,
            fee
        ));
        return ISlipstreamHelper(SLIPSTREAM_HELPER).getEarnedRewards(positionHash);
    }
    
    /// @notice Get Velodrome LP balance
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable Stable pair flag
    /// @return balance LP token balance
    /// @return staked Staked LP balance
    /// @return total Total LP balance (balance + staked)
    function getVelodromeLPBalance(
        address tokenA,
        address tokenB,
        bool stable
    )
        external
        view
        returns (
            uint256 balance,
            uint256 staked,
            uint256 total
        )
    {
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        balance = vault.getVeloLPBalance(tokenA, tokenB, stable);
        staked = vault.getVeloStakedLPBalance(tokenA, tokenB, stable);
        total = vault.getVeloTotalLPBalance(tokenA, tokenB, stable);
    }
    
    /// @notice Get comprehensive summary for multiple tokens
    /// @param tokens Array of token addresses
    /// @return summaries Array of token summaries
    function getMultiTokenSummary(address[] calldata tokens)
        external
        view
        returns (TokenSummary[] memory summaries)
    {
        uint256 length = tokens.length;
        summaries = new TokenSummary[](length);
        
        BundledYieldVaultV2__MULTICALL vault = BundledYieldVaultV2__MULTICALL(VAULT);
        
        for (uint256 i = 0; i < length;) {
            address token = tokens[i];
            
            (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, uint256 gasBalance) =
                vault.getStatus(token);
            
            uint256 apyBps = vault.getCurrentAPY(token);
            (bool isHealthy, bool hasGas, bool hasYield, uint256 timeSinceLastUpdate, uint256 totalValueLocked) =
                vault.getVaultHealth(token);
            
            summaries[i] = TokenSummary({
                token: token,
                depositedAmount: depositedAmount,
                currentBalance: currentBalance,
                yieldAvailable: yieldAvailable,
                apyBps: apyBps,
                isHealthy: isHealthy,
                hasGas: hasGas,
                hasYield: hasYield,
                timeSinceLastUpdate: timeSinceLastUpdate,
                totalValueLocked: totalValueLocked,
                gasBalance: gasBalance
            });
            
            unchecked {
                ++i;
            }
        }
    }
    
    /// @notice Token summary struct
    struct TokenSummary {
        address token;
        uint256 depositedAmount;
        uint256 currentBalance;
        uint256 yieldAvailable;
        uint256 apyBps;
        bool isHealthy;
        bool hasGas;
        bool hasYield;
        uint256 timeSinceLastUpdate;
        uint256 totalValueLocked;
        uint256 gasBalance;
    }
}

