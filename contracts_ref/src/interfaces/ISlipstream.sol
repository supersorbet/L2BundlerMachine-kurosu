// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Slipstream (Velodrome V3) Position NFT interface
/// @dev ERC-721 NFT representing a concentrated liquidity position
interface ISlipstreamPositionNFT {
    /// @notice Mint a new position NFT
    /// @param params Parameters for creating the position
    /// @return tokenId The token ID of the minted NFT
    function mint(MintParams calldata params) external payable returns (uint256 tokenId);
    
    /// @notice Collect fees from a position
    /// @param tokenId The NFT token ID
    /// @param recipient Address to receive collected fees
    /// @return amount0 Amount of token0 collected
    /// @return amount1 Amount of token1 collected
    function collect(uint256 tokenId, address recipient) external returns (uint256 amount0, uint256 amount1);
    
    /// @notice Increase liquidity in a position
    /// @param tokenId The NFT token ID
    /// @param params Parameters for increasing liquidity
    /// @return liquidity The new liquidity amount
    /// @return amount0 Amount of token0 added
    /// @return amount1 Amount of token1 added
    function increaseLiquidity(uint256 tokenId, IncreaseLiquidityParams calldata params) 
        external 
        payable 
        returns (uint256 liquidity, uint256 amount0, uint256 amount1);
    
    /// @notice Decrease liquidity in a position
    /// @param tokenId The NFT token ID
    /// @param params Parameters for decreasing liquidity
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function decreaseLiquidity(uint256 tokenId, DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);
    
    /// @notice Burn a position NFT (after removing all liquidity)
    /// @param tokenId The NFT token ID
    function burn(uint256 tokenId) external;
    
    /// @notice Get position details
    /// @param tokenId The NFT token ID
    /// @return token0 Token0 address
    /// @return token1 Token1 address
    /// @return fee Fee tier
    /// @return tickLower Lower tick
    /// @return tickUpper Upper tick
    /// @return liquidity Current liquidity
    function positions(uint256 tokenId)
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        );
    
    /// @notice Get the owner of an NFT
    /// @param tokenId The NFT token ID
    /// @return owner The owner address
    function ownerOf(uint256 tokenId) external view returns (address owner);
    
    /// @notice Get balance of NFTs for an address
    /// @param owner The owner address
    /// @return balance The number of NFTs owned
    function balanceOf(address owner) external view returns (uint256 balance);
    
    /// @notice Transfer NFT to another address
    /// @param from From address
    /// @param to To address
    /// @param tokenId The NFT token ID
    function transferFrom(address from, address to, uint256 tokenId) external;
    
    /// @notice Approve an address to transfer NFT
    /// @param to Approved address
    /// @param tokenId The NFT token ID
    function approve(address to, uint256 tokenId) external;
    
    /// @notice Get approved address for an NFT
    /// @param tokenId The NFT token ID
    /// @return operator Approved address
    function getApproved(uint256 tokenId) external view returns (address operator);
    
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    
    struct IncreaseLiquidityParams {
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    
    struct DecreaseLiquidityParams {
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
}

/// @notice LeafCLGauge interface (for staking Slipstream position NFTs)
/// @dev Gauge contract for earning rewards on staked NFT positions
interface ILeafCLGauge {
    /// @notice Stake a position NFT
    /// @param tokenId The NFT token ID to stake
    function stake(uint256 tokenId) external;
    
    /// @notice Unstake a position NFT
    /// @param tokenId The NFT token ID to unstake
    function unstake(uint256 tokenId) external;
    
    /// @notice Harvest rewards for staked positions
    /// @param tokenIds Array of NFT token IDs to harvest for
    /// @return rewards Amount of rewards harvested
    function harvest(uint256[] calldata tokenIds) external returns (uint256 rewards);
    
    /// @notice Get staked token IDs for an account
    /// @param account The account address
    /// @return tokenIds Array of staked NFT token IDs
    function stakedTokens(address account) external view returns (uint256[] memory tokenIds);
    
    /// @notice Check if a token ID is staked
    /// @param tokenId The NFT token ID
    /// @return staked True if staked
    /// @return owner The owner of the staked position
    function staked(uint256 tokenId) external view returns (bool staked, address owner);
    
    /// @notice Get earned rewards for an account
    /// @param account The account address
    /// @return rewards Amount of rewards earned
    function earned(address account) external view returns (uint256 rewards);
    
    /// @notice Get total staked positions count
    /// @return count Total number of staked positions
    function totalStaked() external view returns (uint256 count);
}

