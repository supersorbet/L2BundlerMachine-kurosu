// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ISlipstreamPositionNFT, ILeafCLGauge} from "./interfaces/ISlipstream.sol";
import {IVeloRouter} from "./interfaces/IVelodrome.sol";

/// @title SlipstreamHelper
/// @notice Helper contract for Slipstream V3 (NFT position) operations on Ink L2
/// @dev Reduces main vault contract size by moving Slipstream logic here
/// @author sorbet//pepecoin core
contract SlipstreamHelper {
    using SafeTransferLib for address;

    error Unauthorized();
    /// @dev Error for unauthorized access
    error VaultAlreadySet();
    /// @dev Error for vault not set
    error VaultNotSet();
    /// @dev Error for deposit failed
    error DepositFailed();
    /// @dev Error for invalid amount
    error InvalidAmount();
    /// @dev Error for insufficient balance
    error InsufficientBalance();
    /// @dev Error for position not found
    error PositionNotFound();
    /// @dev Error for invalid token id
    error InvalidTokenId();
    /// @dev Error for swap failed
    error SwapFailed();
    
    /// @dev Slipstream Position NFT contract address (on Ink L2)
    address public immutable SLIPSTREAM_POSITION_NFT;
    /// @dev Velodrome Router for swaps (used for zap functionality)
    address public immutable VELO_ROUTER;
    /// @dev Owner of the helper (for initial setup)
    address public owner;
    /// @dev Vault contract that can call this helper
    address public vault;
    /// @dev LeafCLGauge contract for staking NFTs (set per pool)
    mapping(bytes32 => address) public leafGauges;
    
    /// @dev Track position NFTs owned by this helper
    /// @dev Maps position hash -> array of tokenIds
    mapping(bytes32 => uint256[]) public positionTokenIds;
    /// @dev Track tokenId -> positionHash for efficient cleanup
    mapping(uint256 => bytes32) public tokenIdToPositionHash;
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyVault() {
        if (vault == address(0)) revert VaultNotSet();
        if (msg.sender != vault) revert Unauthorized();
        _;
    }
    
    constructor(address _slipstreamPositionNFT, address _veloRouter) {
        if (_slipstreamPositionNFT == address(0)) revert InvalidAmount();
        if (_veloRouter == address(0)) revert InvalidAmount();
        SLIPSTREAM_POSITION_NFT = _slipstreamPositionNFT;
        VELO_ROUTER = _veloRouter;
        owner = msg.sender;
    }
    
    /// @notice Set the vault contract (can only be called once)
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidAmount();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = _vault;
    }
    
    /// @notice Set LeafCLGauge for a token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param fee Fee tier (e.g., 100 = 0.01%)
    /// @param gauge LeafCLGauge contract address
    function setLeafGauge(address tokenA, address tokenB, uint24 fee, address gauge) external onlyVault {
        bytes32 positionHash = _positionHash(tokenA, tokenB, fee);
        leafGauges[positionHash] = gauge;
        emit LeafGaugeSet(positionHash, gauge);
    }
    
    /// @notice Create a new Slipstream position NFT
    /// @param params Mint parameters for the position
    /// @param stakeInGauge If true, stake the NFT in LeafCLGauge after minting
    /// @return tokenId The NFT token ID of the created position
    function createPosition(
        ISlipstreamPositionNFT.MintParams calldata params,
        bool stakeInGauge
    ) external onlyVault returns (uint256 tokenId) {
        if (params.amount0Desired == 0 && params.amount1Desired == 0) revert InvalidAmount();
        if (params.recipient != address(this)) revert InvalidAmount();///Must mint to helper
        if (params.amount0Desired > 0) {
            params.token0.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
            params.token0.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            params.token1.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
            params.token1.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount1Desired);
        }
        try ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).mint(params) returns (uint256 _tokenId) {
            tokenId = _tokenId;
        } catch {
            revert DepositFailed();
        }
        ///Track
        bytes32 positionHash = _positionHash(params.token0, params.token1, params.fee);
        positionTokenIds[positionHash].push(tokenId);
        tokenIdToPositionHash[tokenId] = positionHash;
       ///Optionally stake in gauge 
        if (stakeInGauge) {
            address gauge = leafGauges[positionHash];
            if (gauge != address(0)) {
                address owner = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).ownerOf(tokenId);
                if (owner != address(this)) revert PositionNotFound();
                
                ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).approve(gauge, tokenId);
                ILeafCLGauge(gauge).stake(tokenId);
                emit SlipstreamPositionStaked(positionHash, gauge, tokenId);
            }
        }
        _sendToVault(params.token0);
        _sendToVault(params.token1);

        emit SlipstreamPositionCreated(
            params.token0,
            params.token1,
            params.fee,
            tokenId,
            stakeInGauge
        );
    }

    /// @notice Zap single token into Slipstream position
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address (for the pair)
    /// @param amountIn Amount of tokenIn to zap
    /// @param fee Fee tier (e.g., 100 = 0.01%)
    /// @param tickLower Lower tick for the position
    /// @param tickUpper Upper tick for the position
    /// @param minAmount0 Minimum amount of token0 (for slippage protection)
    /// @param minAmount1 Minimum amount of token1 (for slippage protection)
    /// @param stakeInGauge If true, stake NFT in LeafCLGauge after minting
    /// @return tokenId The NFT token ID of the created position
    function zapIntoPosition(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 minAmount0,
        uint256 minAmount1,
        bool stakeInGauge
    ) external onlyVault returns (uint256 tokenId) {
        if (amountIn == 0) revert InvalidAmount();
        uint256 swapAmount = amountIn / 2;
        address token0 = tokenIn < tokenOut ? tokenIn : tokenOut;
        address token1 = tokenIn < tokenOut ? tokenOut : tokenIn;
        
        tokenIn.safeApprove(VELO_ROUTER, 0);
        tokenIn.safeApprove(VELO_ROUTER, swapAmount);
        bool isStable = (tokenIn == address(0x0200C29006150606B650577BBE7B6248F58470c1) && tokenOut == address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff)) ||
                        (tokenOut == address(0x0200C29006150606B650577BBE7B6248F58470c1) && tokenIn == address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff));
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0] = IVeloRouter.Route({
            from: tokenIn,
            to: tokenOut,
            stable: isStable,
            factory: address(0)
        });
        uint256 expectedAmountOut = swapAmount; 
        uint256 minAmountOut = (expectedAmountOut * 95) / 100;///5% slippage max
        try IVeloRouter(VELO_ROUTER).swapExactTokensForTokens(
            swapAmount,
            minAmountOut,
            routes,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            uint256 amountOut = amounts[amounts.length - 1];
            uint256 remainingIn = amountIn - swapAmount;
            ISlipstreamPositionNFT.MintParams memory params = ISlipstreamPositionNFT.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: tokenIn == token0 ? remainingIn : amountOut,
                amount1Desired: tokenIn == token0 ? amountOut : remainingIn,
                amount0Min: minAmount0,
                amount1Min: minAmount1,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            });
            if (params.amount0Desired > 0) {
                params.token0.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
                params.token0.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount0Desired);
            }
            if (params.amount1Desired > 0) {
                params.token1.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
                params.token1.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount1Desired);
            }
            try ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).mint(params) returns (uint256 _tokenId) {
                tokenId = _tokenId;
            } catch {
                revert DepositFailed();
            }
            ///Track
            bytes32 positionHash = _positionHash(token0, token1, fee);
            positionTokenIds[positionHash].push(tokenId);
            tokenIdToPositionHash[tokenId] = positionHash;
            ///Optionally stake in gauge
            if (stakeInGauge) {
                address gauge = leafGauges[positionHash];
                if (gauge != address(0)) {
                    address ownerOfNFT = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).ownerOf(tokenId);
                    if (ownerOfNFT != address(this)) revert PositionNotFound();
            
                    ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).approve(gauge, tokenId);
                    ILeafCLGauge(gauge).stake(tokenId);
                    emit SlipstreamPositionStaked(positionHash, gauge, tokenId);
                }
            }
            _sendToVault(token0);
            _sendToVault(token1);
            
            emit SlipstreamPositionCreated(token0, token1, fee, tokenId, stakeInGauge);
            emit SlipstreamZapCompleted(tokenIn, tokenOut, tokenId);
        } catch {
            revert SwapFailed();
        }
    }
    
    /// @notice Increase liquidity in an existing position
    /// @param tokenId The NFT token ID
    /// @param params Increase liquidity parameters
    /// @return liquidity New liquidity amount
    /// @return amount0 Amount of token0 added
    /// @return amount1 Amount of token1 added
    function increaseLiquidity(
        uint256 tokenId,
        ISlipstreamPositionNFT.IncreaseLiquidityParams calldata params
    ) external onlyVault returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        if (tokenId == 0) revert InvalidTokenId();
        (address token0, address token1, , , , ) = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).positions(tokenId);
        if (params.amount0Desired > 0) {
            token0.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
            token0.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            token1.safeApprove(SLIPSTREAM_POSITION_NFT, 0);
            token1.safeApprove(SLIPSTREAM_POSITION_NFT, params.amount1Desired);
        }
        /// Increase liq
        try ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).increaseLiquidity(tokenId, params) 
            returns (uint256 _liquidity, uint256 _amount0, uint256 _amount1) {
            liquidity = _liquidity;
            amount0 = _amount0;
            amount1 = _amount1;
        } catch {
            revert DepositFailed();
        }
        
        _sendToVault(token0);
        _sendToVault(token1);

        emit SlipstreamLiquidityIncreased(tokenId, liquidity, amount0, amount1);
    }
    
    /// @notice Decrease liquidity in a position
    /// @param tokenId The NFT token ID
    /// @param params Decrease liquidity parameters
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function decreaseLiquidity(
        uint256 tokenId,
        ISlipstreamPositionNFT.DecreaseLiquidityParams calldata params
    ) external onlyVault returns (uint256 amount0, uint256 amount1) {
        if (tokenId == 0) revert InvalidTokenId();
        try ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).decreaseLiquidity(tokenId, params)
            returns (uint256 _amount0, uint256 _amount1) {
            amount0 = _amount0;
            amount1 = _amount1;
        } catch {
            revert DepositFailed();
        }
        
        (address token0, address token1, , , , ) = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).positions(tokenId);
        _sendToVault(token0);
        _sendToVault(token1);

        emit SlipstreamLiquidityDecreased(tokenId, amount0, amount1);
    }
    
    /// @notice Collect fees from a position
    /// @param tokenId The NFT token ID
    /// @param recipient Address to receive collected fees (typically vault)
    /// @return amount0 Amount of token0 collected
    /// @return amount1 Amount of token1 collected
    function collectFees(uint256 tokenId, address recipient) 
        external 
        onlyVault 
        returns (uint256 amount0, uint256 amount1) 
    {
        if (tokenId == 0) revert InvalidTokenId();
        if (recipient == address(0)) revert InvalidAmount();
        try ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).collect(tokenId, recipient)
            returns (uint256 _amount0, uint256 _amount1) {
            amount0 = _amount0;
            amount1 = _amount1;
        } catch {
            revert DepositFailed();
        }
        
        (address token0, address token1, , , , ) = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).positions(tokenId);
        _sendToVault(token0);
        _sendToVault(token1);

        emit SlipstreamFeesCollected(tokenId, amount0, amount1);
    }
    
    /// @notice Harvest rewards from staked positions
    /// @param positionHash Position hash (token0, token1, fee)
    /// @return rewards Amount of rewards harvested
    function harvestRewards(bytes32 positionHash) external onlyVault returns (uint256 rewards) {
        address gauge = leafGauges[positionHash];
        if (gauge == address(0)) revert InvalidAmount();
       ///Get all staked token IDs for this position
        uint256[] memory tokenIds = positionTokenIds[positionHash];
        if (tokenIds.length == 0) return 0;
       ///Filter to only staked token IDs
        uint256[] memory stakedTokenIds = new uint256[](tokenIds.length);
        uint256 stakedCount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (bool isStaked, ) = ILeafCLGauge(gauge).staked(tokenIds[i]);
            if (isStaked) {
                stakedTokenIds[stakedCount] = tokenIds[i];
                stakedCount++;
            }
        }
        
        if (stakedCount == 0) return 0;
        assembly {
            mstore(stakedTokenIds, stakedCount)
        }
       ///Harvest rewards
        try ILeafCLGauge(gauge).harvest(stakedTokenIds) returns (uint256 _rewards) {
            rewards = _rewards;
        } catch {
            rewards = 0;///Don't revert, just return 0
        }
        
        emit SlipstreamRewardsHarvested(positionHash, gauge, rewards);
    }
    
    /// @notice Stake a position NFT in LeafCLGauge
    /// @param tokenId The NFT token ID
    /// @param positionHash Position hash (token0, token1, fee)
    function stakePosition(uint256 tokenId, bytes32 positionHash) external onlyVault {
        if (tokenId == 0) revert InvalidTokenId();
        address gauge = leafGauges[positionHash];
        if (gauge == address(0)) revert InvalidAmount();
       ///Verify helper owns NFT
        address owner = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).ownerOf(tokenId);
        if (owner != address(this)) revert PositionNotFound();
        ///Check if already staked
        (bool isStaked, ) = ILeafCLGauge(gauge).staked(tokenId);
        if (isStaked) revert InvalidAmount();
       ///Update tracking if not already tracked
        if (tokenIdToPositionHash[tokenId] == bytes32(0)) {
            positionTokenIds[positionHash].push(tokenId);
            tokenIdToPositionHash[tokenId] = positionHash;
        }

        ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).approve(gauge, tokenId);
        ILeafCLGauge(gauge).stake(tokenId);
        
        emit SlipstreamPositionStaked(positionHash, gauge, tokenId);
    }
    
    /// @notice Unstake a position NFT from LeafCLGauge
    /// @param tokenId The NFT token ID
    /// @param positionHash Position hash (token0, token1, fee)
    function unstakePosition(uint256 tokenId, bytes32 positionHash) external onlyVault {
        if (tokenId == 0) revert InvalidTokenId();
        address gauge = leafGauges[positionHash];
        if (gauge == address(0)) revert InvalidAmount();
        (bool isStaked, ) = ILeafCLGauge(gauge).staked(tokenId);
        if (!isStaked) revert InvalidAmount();
        
        ILeafCLGauge(gauge).unstake(tokenId);
        
        emit SlipstreamPositionUnstaked(positionHash, gauge, tokenId);
    }
    
    /// @notice Transfer position NFT to recipient (e.g., owner EOA for UI visibility)
    /// @param tokenId The NFT token ID
    /// @param to Recipient address
    function transferPosition(uint256 tokenId, address to) external onlyVault {
        if (tokenId == 0) revert InvalidTokenId();
        if (to == address(0)) revert InvalidAmount();
        
        address owner = ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).ownerOf(tokenId);
        if (owner != address(this)) revert PositionNotFound();
        /// @dev Remove from tracking array before transfer
        bytes32 positionHash = tokenIdToPositionHash[tokenId];
        if (positionHash != bytes32(0)) {
            uint256[] storage tokenIds = positionTokenIds[positionHash];
            uint256 length = tokenIds.length;
            for (uint256 i = 0; i < length; i++) {
                if (tokenIds[i] == tokenId) {
                    tokenIds[i] = tokenIds[length - 1];
                    tokenIds.pop();
                    break;
                }
            }
            delete tokenIdToPositionHash[tokenId];
        }
        ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).transferFrom(address(this), to, tokenId);
        
        emit SlipstreamPositionTransferred(tokenId, to);
    }
    
    /// @notice Get all position token IDs for a position hash
    /// @param positionHash Position hash (token0, token1, fee)
    /// @return tokenIds Array of NFT token IDs
    function getPositionTokenIds(bytes32 positionHash) external view returns (uint256[] memory) {
        return positionTokenIds[positionHash];
    }
    
    /// @notice Get staked token IDs for a position
    /// @param positionHash Position hash (token0, token1, fee)
    /// @return tokenIds Array of staked NFT token IDs
    function getStakedTokenIds(bytes32 positionHash) external view returns (uint256[] memory) {
        address gauge = leafGauges[positionHash];
        if (gauge == address(0)) return new uint256[](0);
        
        return ILeafCLGauge(gauge).stakedTokens(vault);
    }
    
    /// @notice Get earned rewards for a position
    /// @param positionHash Position hash (token0, token1, fee)
    /// @return rewards Amount of rewards earned
    function getEarnedRewards(bytes32 positionHash) external view returns (uint256 rewards) {
        address gauge = leafGauges[positionHash];
        if (gauge == address(0)) return 0;
        
        return ILeafCLGauge(gauge).earned(vault);
    }
    
    /// @notice Get position details
    /// @param tokenId The NFT token ID
    /// @return token0 Token0 address
    /// @return token1 Token1 address
    /// @return fee Fee tier
    /// @return tickLower Lower tick
    /// @return tickUpper Upper tick
    /// @return liquidity Current liquidity
    function getPosition(uint256 tokenId)
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
        return ISlipstreamPositionNFT(SLIPSTREAM_POSITION_NFT).positions(tokenId);
    }
    
    /// @notice Generate position hash (token0, token1, fee)
    function _positionHash(address tokenA, address tokenB, uint24 fee) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1, fee));
    }
    
    /// @notice Generate position hash (public for testing)
    function positionHash(address tokenA, address tokenB, uint24 fee) external pure returns (bytes32) {
        return _positionHash(tokenA, tokenB, fee);
    }

    event LeafGaugeSet(bytes32 indexed positionHash, address indexed gauge);
    event SlipstreamPositionCreated(
        address indexed token0,
        address indexed token1,
        uint24 fee,
        uint256 indexed tokenId,
        bool staked
    );
    event SlipstreamLiquidityIncreased(uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SlipstreamLiquidityDecreased(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event SlipstreamFeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event SlipstreamRewardsHarvested(bytes32 indexed positionHash, address indexed gauge, uint256 rewards);
    event SlipstreamPositionStaked(bytes32 indexed positionHash, address indexed gauge, uint256 indexed tokenId);
    event SlipstreamPositionUnstaked(bytes32 indexed positionHash, address indexed gauge, uint256 indexed tokenId);
    event SlipstreamPositionTransferred(uint256 indexed tokenId, address indexed to);
    event SlipstreamZapCompleted(address indexed tokenIn, address indexed tokenOut, uint256 indexed tokenId);

    function _sendToVault(address token) internal {
        if (vault == address(0) || token == address(0)) return;
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance > 0) {
            token.safeTransfer(vault, balance);
        }
    }
}


