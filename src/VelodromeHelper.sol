// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IVeloRouter, IVeloPair, IVeloGauge, IVeloVoter} from "./interfaces/IVelodrome.sol";
import {IVelodromeUniversalRouter} from "./interfaces/IVelodromeUniversalRouter.sol";
import {VelodromeCommandEncoder} from "./interfaces/IVelodromeUniversalRouter.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";

/// @title VelodromeHelper
/// @notice Helper contract for Velodrome LP operations
/// @dev Reduces main vault contract size by moving Velodrome logic here
/// @author sorbet/pepecoin core
contract VelodromeHelper {
    using SafeTransferLib for address;

    error Unauthorized();
    /// @dev Error for vault already set
    error VaultAlreadySet();
    /// @dev Error for vault not set    
    error VaultNotSet();
    /// @dev Error for deposit failed
    error DepositFailed();
    /// @dev Error for invalid amount
    error InvalidAmount();
    /// @dev Error for insufficient balance
    error InsufficientBalance();
    
    /// @dev Velodrome Router address
    address public immutable VELO_ROUTER;
    /// @dev Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @dev Owner of the helper
    address public owner;
    /// @dev Vault contract that can call this helper
    address public vault;
    /// @dev Velodrome Voter address
    address public veloVoter;
    
    /// @dev Mapping from pair hash to pair address
    mapping(bytes32 => address) public veloPairs;
    /// @dev Mapping from pair hash to gauge address
    mapping(bytes32 => address) public veloGauges;
    
    /// @dev Modifier to check if the caller is the owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    /// @dev Modifier to check if the caller is the vault
    modifier onlyVault() {
        if (vault == address(0)) revert VaultNotSet();
        if (msg.sender != vault) revert Unauthorized();
        _;
    }
    
    constructor(address _veloRouter) {
        VELO_ROUTER = _veloRouter;
        owner = msg.sender;
    }
    
    /// @notice Set the vault contract
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidAmount();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = _vault;
    }
    
    /// @notice Set the Velodrome Voter contract
    function setVeloVoter(address _veloVoter) external onlyVault {
        veloVoter = _veloVoter;
    }
    
    /// @notice Create LP position with optional staking
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param amountA Amount of token A
    /// @param amountB Amount of token B
    /// @param stable Whether the pair is stable
    /// @param stakeInGauge Whether to stake in gauge
    /// @return liquidity Liquidity created
    function createLP(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable,
        bool stakeInGauge
    ) external onlyVault returns (uint256 liquidity) {
        if (amountA == 0 || amountB == 0) revert InvalidAmount();
        _approveRouter(tokenA, amountA);
        _approveRouter(tokenB, amountB);
        (uint256 usedA, uint256 usedB, uint256 liq) = _tryAddLiquidity(
            tokenA,
            tokenB,
            stable,
            amountA,
            amountB
        );
        
        liquidity = liq;
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
        veloPairs[pairHash] = pair;
        
        if (stakeInGauge && veloVoter != address(0)) {
            address gauge = IVeloVoter(veloVoter).gauges(pair);
            if (gauge != address(0)) {
                pair.safeApprove(gauge, liquidity);
                IVeloGauge(gauge).deposit(liquidity, vault);
                veloGauges[pairHash] = gauge;
                emit VelodromeLPStaked(pairHash, gauge, liquidity);
            }
        }
        if (usedA < amountA) tokenA.safeTransfer(vault, amountA - usedA);
        if (usedB < amountB) tokenB.safeTransfer(vault, amountB - usedB);
        
        emit VelodromeLPCreated(tokenA, tokenB, stable, liquidity, stakeInGauge);
    }
    
    /// @notice Zap single token into LP
    /// @param tokenIn Token in address
    /// @param tokenOut Token out address
    /// @param amountIn Amount of token in
    /// @param stable Whether the pair is stable
    /// @param stakeInGauge Whether to stake in gauge
    /// @param minLiquidity Minimum liquidity to create
    /// @return liquidity Liquidity created
    function zapIntoLP(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool stable,
        bool stakeInGauge,
        uint256 minLiquidity
    ) external onlyVault returns (uint256 liquidity) {
        if (amountIn == 0) revert InvalidAmount();
        uint256 swapAmount = amountIn / 2;
        _approveRouter(tokenIn, swapAmount);
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0] = IVeloRouter.Route({
            from: tokenIn,
            to: tokenOut,
            stable: stable,
            factory: address(0)
        });
        ///calculate minimum amount out based on slippage tolerance (5%)
        ///WITH SStable pairs, expect ~1:1 ratio. For volatile pairs, this is approximate.
        uint256 expectedAmountOut = swapAmount; 
        uint256 minAmountOut = (expectedAmountOut * 95) / 100; ///5% slippage

        uint256[] memory amounts = IVeloRouter(VELO_ROUTER).swapExactTokensForTokens(
            swapAmount,
            minAmountOut,
            routes,
            address(this),
            block.timestamp
        );
        
        uint256 amountOut = amounts[amounts.length - 1];
        uint256 remainingIn = amountIn - swapAmount;
        _approveRouter(tokenIn, remainingIn);
        _approveRouter(tokenOut, amountOut);
        
        (uint256 usedA, uint256 usedB, uint256 liq) = _tryAddLiquidity(
            tokenIn,
            tokenOut,
            stable,
            remainingIn,
            amountOut
        );
        
        liquidity = liq;
        if (liquidity < minLiquidity) revert InvalidAmount();
        bytes32 pairHash = _veloPairHash(tokenIn, tokenOut, stable);
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenIn, tokenOut, stable);
        veloPairs[pairHash] = pair;
        
        if (stakeInGauge && veloVoter != address(0)) {
            address gauge = IVeloVoter(veloVoter).gauges(pair);
            if (gauge != address(0)) {
                pair.safeApprove(gauge, liquidity);
                IVeloGauge(gauge).deposit(liquidity, vault);
                veloGauges[pairHash] = gauge;
                emit VelodromeLPStaked(pairHash, gauge, liquidity);
            }
        }
        if (usedA < remainingIn) tokenIn.safeTransfer(vault, remainingIn - usedA);
        if (usedB < amountOut) tokenOut.safeTransfer(vault, amountOut - usedB);
        
        emit VelodromeLPCreated(tokenIn, tokenOut, stable, liquidity, stakeInGauge);
    }
    
    /// @notice Harvest rewards from gauge
    /// @param pairHash Pair hash (from _veloPairHash)
    /// @return harvested Amount of rewards harvested
    function harvestRewards(bytes32 pairHash) external onlyVault returns (uint256 harvested) {
        address gauge = veloGauges[pairHash];
        if (gauge == address(0)) revert InvalidAmount();
        
        uint256 earnedBefore = IVeloGauge(gauge).earned(vault);
        IVeloGauge(gauge).getReward(vault);
        uint256 earnedAfter = IVeloGauge(gauge).earned(vault);
        
        harvested = earnedBefore > earnedAfter ? earnedBefore - earnedAfter : earnedBefore;
        emit VelodromeRewardsHarvested(pairHash, gauge, harvested);
    }
    
    /// @notice Harvest fees from pair
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @return fee0 Amount of fee0 harvested
    /// @return fee1 Amount of fee1 harvested
    function harvestFees(address tokenA, address tokenB, bool stable) external onlyVault returns (uint256 fee0, uint256 fee1) {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        address pair = veloPairs[pairHash];
        if (pair == address(0)) {
            pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
            if (pair == address(0)) revert InvalidAmount();
            veloPairs[pairHash] = pair;
        }
        
        (fee0, fee1) = IVeloPair(pair).claimFees();
        emit VelodromeFeesHarvested(pairHash, pair, fee0, fee1);
    }
    
    /// @notice Get gauge for pair
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @return gauge Gauge address
    function getGauge(address tokenA, address tokenB, bool stable) external view returns (address gauge) {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        gauge = veloGauges[pairHash];
        if (gauge == address(0) && veloVoter != address(0)) {
            address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
            if (pair != address(0)) {
                gauge = IVeloVoter(veloVoter).gauges(pair);
            }
        }
    }
    
    /// @notice Transfer LP tokens (for sending to owner EOA)
    /// @param pair Pair address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    function transferLP(address pair, address to, uint256 amount) external onlyVault {
        ///check if we have LP balance
        uint256 balance = IVeloPair(pair).balanceOf(address(this));
        if (balance < amount) {
            ///LP might be staked, try to get from gauge
            ///TODO: full implementation depending on team's opinion?
            revert InsufficientBalance();
        }
        pair.safeTransfer(to, amount);
    }

    /// @notice Get LP balance for a pair (helper contract balance)
    /// @param pairHash Pair hash (from _veloPairHash)
    /// @return balance LP token balance in helper
    function getLPBalance(bytes32 pairHash) external view returns (uint256 balance) {
        address pair = veloPairs[pairHash];
        if (pair == address(0)) return 0;
        balance = IVeloPair(pair).balanceOf(address(this));
    }

    /// @notice Get staked LP balance in gauge
    /// @param pairHash Pair hash (from _veloPairHash)
    /// @return staked Amount of LP tokens staked in gauge
    function getStakedLPBalance(bytes32 pairHash) external view returns (uint256 staked) {
        address gauge = veloGauges[pairHash];
        if (gauge == address(0)) return 0;
        staked = IVeloGauge(gauge).balanceOf(vault);
    }

    /// @notice Get total LP balance (helper + staked)
    /// @param pairHash Pair hash (from _veloPairHash)
    /// @return total Total LP tokens (helper + staked)
    function getTotalLPBalance(bytes32 pairHash) external view returns (uint256 total) {
        address pair = veloPairs[pairHash];
        address gauge = veloGauges[pairHash];

        uint256 helperBalance = pair == address(0) ? 0 : IVeloPair(pair).balanceOf(address(this));
        uint256 stakedBalance = gauge == address(0) ? 0 : IVeloGauge(gauge).balanceOf(vault);

        total = helperBalance + stakedBalance;
    }

    /// @notice Unstake LP tokens from gauge back to helper contract
    /// @param pairHash Pair hash (from _veloPairHash)
    /// @param amount Amount to unstake (0 = unstake all)
    /// @return unstaked Amount of LP tokens unstaked
    function unstakeLP(bytes32 pairHash, uint256 amount) external onlyVault returns (uint256 unstaked) {
        address gauge = veloGauges[pairHash];
        if (gauge == address(0)) revert InvalidAmount();

        uint256 stakedBalance = IVeloGauge(gauge).balanceOf(vault);
        if (stakedBalance == 0) revert InsufficientBalance();
        if (amount == 0 || amount > stakedBalance) {
            amount = stakedBalance;
        }

        IVeloGauge(gauge).withdraw(amount);
        unstaked = amount;
    }
    
    /// @notice Try addLiquidity with Universal Router fallback
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @param amountA Amount of token A
    /// @param amountB Amount of token B
    /// @return usedA Amount of token A used
    /// @return usedB Amount of token B used
    /// @return liquidity Amount of liquidity created
    function _tryAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 usedA, uint256 usedB, uint256 liquidity) {
        try IVeloRouter(VELO_ROUTER).addLiquidity(
            tokenA,
            tokenB,
            stable,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        ) returns (uint256 _usedA, uint256 _usedB, uint256 _liquidity) {
            return (_usedA, _usedB, _liquidity);
        } catch {
            (bytes1 command, bytes memory input) = VelodromeCommandEncoder.encodeAddLiquidity(
                false,
                tokenA,
                tokenB,
                stable,
                amountA,
                amountB,
                0,
                0,
                address(this),
                block.timestamp
            );
            
            bytes[] memory inputs = new bytes[](1);
            inputs[0] = input;
            
            IVelodromeUniversalRouter(VELO_ROUTER).execute(
                abi.encodePacked(command),
                inputs
            );
            
            address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
            if (pair == address(0)) revert DepositFailed();
            
            liquidity = IVeloPair(pair).balanceOf(address(this));
            usedA = amountA;
            usedB = amountB;
            
            return (usedA, usedB, liquidity);
        }
    }
    
    /// @notice Generate pair hash
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @return pairHash Pair hash
    function _veloPairHash(address tokenA, address tokenB, bool stable) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1, stable));
    }

    /// @notice Generate Velodrome pair hash 
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @return pairHash Pair hash
    function veloPairHash(address tokenA, address tokenB, bool stable) external pure returns (bytes32) {
        return _veloPairHash(tokenA, tokenB, stable);
    }

    /// @notice Approve router with Permit2 fallback
    /// @param token Token address
    /// @param amount Amount to approve
    function _approveRouter(address token, uint256 amount) internal {
        if (amount == 0) return;
        token.safeApprove(VELO_ROUTER, 0);
        token.safeApprove(VELO_ROUTER, amount);
        unchecked {
            uint160 amt160 = amount > type(uint160).max ? type(uint160).max : uint160(amount);
            uint48 expiration = uint48(block.timestamp + 30 days);
            try IPermit2(PERMIT2).approve(token, VELO_ROUTER, amt160, expiration) {} catch {}
        }
    }

    /// @notice Event for LP created
    /// @param tokenA Token A address
    /// @param tokenB Token B address
    /// @param stable Whether the pair is stable
    /// @param liquidity Amount of liquidity created
    /// @param staked Whether the LP is staked
    event VelodromeLPCreated(address indexed tokenA, address indexed tokenB, bool stable, uint256 liquidity, bool staked);
    /// @notice Event for LP staked
    /// @param pairHash Pair hash
    /// @param gauge Gauge address
    /// @param amount Amount of LP tokens staked
    event VelodromeLPStaked(bytes32 indexed pairHash, address indexed gauge, uint256 amount);
    /// @notice Event for rewards harvested
    /// @param pairHash Pair hash
    /// @param gauge Gauge address
    /// @param amount Amount of rewards harvested
    event VelodromeRewardsHarvested(bytes32 indexed pairHash, address indexed gauge, uint256 amount);
    /// @notice Event for fees harvested
    /// @param pairHash Pair hash
    /// @param pair Pair address
    /// @param fee0 Amount of fee0 harvested
    /// @param fee1 Amount of fee1 harvested
    event VelodromeFeesHarvested(bytes32 indexed pairHash, address indexed pair, uint256 fee0, uint256 fee1);
    
}

