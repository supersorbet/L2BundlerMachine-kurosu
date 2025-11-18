// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IVeloRouter, IVeloPair, IVeloGauge, IVeloVoter} from "../interfaces/IVelodrome.sol";
import {IVelodromeUniversalRouter} from "../interfaces/IVelodromeUniversalRouter.sol";
import {VelodromeCommandEncoder} from "../interfaces/IVelodromeUniversalRouter.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";

/// @title VelodromeUtils
/// @notice Utility contract for EOA to interact with Velodrome directly
/// @dev Call from your EOA to create LPs, zap, stake - positions will show in Velodrome UI
contract VelodromeUtils {
    using SafeTransferLib for address;
    
    address public immutable VELO_ROUTER;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public veloVoter;
    
    error DepositFailed();
    error InvalidAmount();
    
    event LPCreated(address indexed tokenA, address indexed tokenB, bool stable, uint256 liquidity, address indexed owner);
    event LPStaked(address indexed pair, address indexed gauge, uint256 amount, address indexed owner);
    event RewardsHarvested(address indexed gauge, uint256 amount, address indexed owner);
    event FeesHarvested(address indexed pair, uint256 fee0, uint256 fee1, address indexed owner);
    
    constructor(address _veloRouter, address _veloVoter) {
        VELO_ROUTER = _veloRouter;
        veloVoter = _veloVoter;
    }
    
    function setVeloVoter(address _veloVoter) external {
        veloVoter = _veloVoter;
    }
    
    /// @notice Create LP position - tokens come from msg.sender, LP goes to msg.sender
    function createLP(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable,
        bool stakeInGauge
    ) external returns (uint256 liquidity) {
        if (amountA == 0 || amountB == 0) revert InvalidAmount();
        
        // Transfer tokens from caller
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        
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
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
        
        // Transfer LP tokens to caller (so they show in Velodrome UI)
        pair.safeTransfer(msg.sender, liquidity);
        
        // If staking, transfer LP back to this contract, then stake
        if (stakeInGauge && veloVoter != address(0)) {
            address gauge = IVeloVoter(veloVoter).gauges(pair);
            if (gauge != address(0)) {
                pair.safeTransferFrom(msg.sender, address(this), liquidity);
                pair.safeApprove(gauge, liquidity);
                IVeloGauge(gauge).deposit(liquidity, msg.sender); // Stake on behalf of caller
                emit LPStaked(pair, gauge, liquidity, msg.sender);
            }
        }
        
        // Return dust to caller
        if (usedA < amountA) tokenA.safeTransfer(msg.sender, amountA - usedA);
        if (usedB < amountB) tokenB.safeTransfer(msg.sender, amountB - usedB);
        
        emit LPCreated(tokenA, tokenB, stable, liquidity, msg.sender);
    }
    
    /// @notice Zap single token into LP - LP goes to msg.sender
    function zapIntoLP(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool stable,
        bool stakeInGauge,
        uint256 minLiquidity
    ) external returns (uint256 liquidity) {
        if (amountIn == 0) revert InvalidAmount();
        
        // Transfer input token from caller
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        
        uint256 swapAmount = amountIn / 2;
        _approveRouter(tokenIn, swapAmount);
        
        IVeloRouter.Route[] memory routes = new IVeloRouter.Route[](1);
        routes[0] = IVeloRouter.Route({
            from: tokenIn,
            to: tokenOut,
            stable: stable,
            factory: address(0)
        });
        
        uint256[] memory amounts = IVeloRouter(VELO_ROUTER).swapExactTokensForTokens(
            swapAmount,
            0,
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
        
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenIn, tokenOut, stable);
        
        // Transfer LP to caller
        pair.safeTransfer(msg.sender, liquidity);
        
        if (stakeInGauge && veloVoter != address(0)) {
            address gauge = IVeloVoter(veloVoter).gauges(pair);
            if (gauge != address(0)) {
                pair.safeTransferFrom(msg.sender, address(this), liquidity);
                pair.safeApprove(gauge, liquidity);
                IVeloGauge(gauge).deposit(liquidity, msg.sender);
                emit LPStaked(pair, gauge, liquidity, msg.sender);
            }
        }
        
        // Return dust
        if (usedA < remainingIn) tokenIn.safeTransfer(msg.sender, remainingIn - usedA);
        if (usedB < amountOut) tokenOut.safeTransfer(msg.sender, amountOut - usedB);
        
        emit LPCreated(tokenIn, tokenOut, stable, liquidity, msg.sender);
    }
    
    /// @notice Batch create multiple LPs
    function batchCreateLP(
        address[] calldata tokenAs,
        address[] calldata tokenBs,
        uint256[] calldata amountAs,
        uint256[] calldata amountBs,
        bool[] calldata stables,
        bool[] calldata stakeInGauges
    ) external returns (uint256[] memory liquidities) {
        uint256 len = tokenAs.length;
        require(len == tokenBs.length && len == amountAs.length && len == amountBs.length && len == stables.length && len == stakeInGauges.length, "Length mismatch");
        
        liquidities = new uint256[](len);
        
        for (uint256 i = 0; i < len; i++) {
            liquidities[i] = this.createLP(
                tokenAs[i],
                tokenBs[i],
                amountAs[i],
                amountBs[i],
                stables[i],
                stakeInGauges[i]
            );
        }
    }
    
    /// @notice Stake LP tokens in gauge
    function stakeLP(address pair, uint256 amount) external {
        if (veloVoter == address(0)) revert InvalidAmount();
        address gauge = IVeloVoter(veloVoter).gauges(pair);
        if (gauge == address(0)) revert InvalidAmount();
        
        pair.safeTransferFrom(msg.sender, address(this), amount);
        pair.safeApprove(gauge, amount);
        IVeloGauge(gauge).deposit(amount, msg.sender);
        emit LPStaked(pair, gauge, amount, msg.sender);
    }
    
    /// @notice Harvest rewards from gauge
    function harvestRewards(address gauge) external returns (uint256 harvested) {
        uint256 earnedBefore = IVeloGauge(gauge).earned(msg.sender);
        IVeloGauge(gauge).getReward(msg.sender);
        uint256 earnedAfter = IVeloGauge(gauge).earned(msg.sender);
        
        harvested = earnedBefore > earnedAfter ? earnedBefore - earnedAfter : earnedBefore;
        emit RewardsHarvested(gauge, harvested, msg.sender);
    }
    
    /// @notice Harvest fees from LP pair
    function harvestFees(address pair) external returns (uint256 fee0, uint256 fee1) {
        (fee0, fee1) = IVeloPair(pair).claimFees();
        emit FeesHarvested(pair, fee0, fee1, msg.sender);
    }
    
    /// @notice Get gauge address for a pair
    function getGauge(address pair) external view returns (address gauge) {
        if (veloVoter != address(0)) {
            gauge = IVeloVoter(veloVoter).gauges(pair);
        }
    }
    
    /// @notice Get pair address
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair) {
        pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
    }
    
    /// @notice Try addLiquidity with Universal Router fallback
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
    
    /// @notice Approve router with Permit2 fallback
    function _approveRouter(address token, uint256 amount) internal {
        if (amount == 0) return;
        token.safeApprove(VELO_ROUTER, 0);
        token.safeApprove(VELO_ROUTER, amount);
        
        // Also set Permit2 allowance for Universal Router
        unchecked {
            uint160 amt160 = amount > type(uint160).max ? type(uint160).max : uint160(amount);
            uint48 expiration = uint48(block.timestamp + 30 days);
            try IPermit2(PERMIT2).approve(token, VELO_ROUTER, amt160, expiration) {} catch {}
        }
    }
}

