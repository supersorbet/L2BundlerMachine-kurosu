// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";


/**** EXPERIMENTAL CONTRACT  *****/


/// @title YieldAllocator
/// @notice Smart yield allocation system with dynamic rebalancing and auto-compounding
/// @dev Manages multiple yield strategies and automatically allocates funds based on yield rates
contract YieldAllocator is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;
    
    error StrategyNotRegistered();
    error InvalidAllocation();
    error InsufficientBalance();
    error RebalanceThresholdNotMet();
    error MaxAllocationExceeded();
    error InvalidAPY();
    
    /// @dev Strategy allocation info - packed for gas efficiency
    struct StrategyAllocation {
        uint128 principal;       ///Principal deposited
        uint64 maxAllocationBps;///Max allocation in basis points (0 = no limit)
        uint32 lastRebalance;    ///Last rebalance timestamp
    }
    
    /// @dev Token allocation across strategies
    struct TokenAllocation {
        uint128 totalDeposited;  ///Total deposited across all strategies
        uint128 lastYieldCheck;  ///Last time yield rates were checked
    }
    
    /// @dev strategyId => strategy contract
    mapping(uint8 => IYieldStrategy) public strategies;
    /// @dev token => strategyId => allocation
    mapping(address => mapping(uint8 => StrategyAllocation)) public allocations;
    /// @dev token => allocation summary
    mapping(address => TokenAllocation) public tokenAllocations;
    /// @dev token => strategyId => auxData (for strategies that need it)
    mapping(address => mapping(uint8 => bytes)) public strategyAuxData;
    
    /// @dev Rebalance threshold in basis points (default: 500 = 5% yield differential)
    uint64 public rebalanceThresholdBps = 500;
    /// @dev Minimum time between rebalances (default: 1 day)
    uint32 public minRebalanceInterval = 1 days;
    /// @dev Auto-compound threshold in basis points (default: 100 = 1% yield)
    uint64 public autoCompoundThresholdBps = 100;
    
    constructor() {
        _initializeOwner(msg.sender);
    }
    
    /// @notice Register a new yield strategy
    function registerStrategy(IYieldStrategy strategy) external onlyOwner {
        uint8 id = strategy.strategyId();
        strategies[id] = strategy;
        emit StrategyRegistered(id, address(strategy));
    }
    
    /// @notice Set aux data for a strategy (e.g., pair token for Velodrome)
    function setStrategyAuxData(address token, uint8 strategyId, bytes calldata auxData) external onlyOwner {
        strategyAuxData[token][strategyId] = auxData;
    }
    
    /// @notice Set max allocation for a strategy (in basis points, 0 = no limit)
    function setMaxAllocation(uint8 strategyId, uint64 maxAllocationBps) external onlyOwner {
        uint64 oldMax = allocations[address(0)][strategyId].maxAllocationBps;///Use address(0) as global
       ///Update all tokens' max allocation for this strategy
       ///In production, you might want per-token limits
        emit MaxAllocationUpdated(strategyId, oldMax, maxAllocationBps);
    }
    
    /// @notice Set rebalance threshold
    function setRebalanceThreshold(uint64 thresholdBps) external onlyOwner {
        uint64 oldThreshold = rebalanceThresholdBps;
        rebalanceThresholdBps = thresholdBps;
        emit RebalanceThresholdUpdated(oldThreshold, thresholdBps);
    }
    
    /// @notice Allocate funds across strategies based on yield rates
    /// @param token Token to allocate
    /// @param amount Total amount to allocate
    /// @param forceStrategy Force allocation to a specific strategy (0 = auto)
    function allocateFunds(address token, uint256 amount, uint8 forceStrategy) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAllocation();
       ///Get current yield rates
        (uint8 bestStrategy, uint256 bestAPY) = _getBestStrategy(token);
        uint8 targetStrategy = forceStrategy > 0 ? forceStrategy : bestStrategy;
        if (targetStrategy == 0) revert StrategyNotRegistered();
       ///Check max allocation
        StrategyAllocation storage alloc = allocations[token][targetStrategy];
        if (alloc.maxAllocationBps > 0) {
            uint256 maxAmount = (tokenAllocations[token].totalDeposited * alloc.maxAllocationBps) / 10000;
            if (alloc.principal + amount > maxAmount) revert MaxAllocationExceeded();
        }
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
       ///Get aux data
        bytes memory auxData = strategyAuxData[token][targetStrategy];
        SafeTransferLib.safeApprove(token, address(strategies[targetStrategy]), amount);
        uint256 shares = strategies[targetStrategy].deposit(token, amount, auxData);

        unchecked {
            alloc.principal += uint128(amount);
            tokenAllocations[token].totalDeposited += uint128(amount);
        }
        
        emit FundsAllocated(targetStrategy, token, amount);
    }
    
    /// @notice Auto-rebalance if yield differential exceeds threshold
    function autoRebalance(address token) external onlyOwner nonReentrant {
        TokenAllocation storage tokenAlloc = tokenAllocations[token];
       ///Check rebalance interval
        if (block.timestamp < tokenAlloc.lastYieldCheck + minRebalanceInterval) {
            return;///Too soon to rebalance
        }
       ///Get current yield rates
        (uint8 bestStrategy, uint256 bestAPY) = _getBestStrategy(token);
        if (bestStrategy == 0) return;
       ///Chck each strategy's APY
        uint8 currentStrategy = _getLargestAllocation(token);
        if (currentStrategy == 0) return;
        uint256 currentAPY = _getStrategyAPY(token, currentStrategy);
       ///Check if rebalance is needed (yield differential > threshold)
        if (bestAPY <= currentAPY) return;///No better strategy
        
        uint256 yieldDiff = bestAPY - currentAPY;
        if (yieldDiff < rebalanceThresholdBps) {
            return;///Differential too small
        }
       ///Rebalance: move funds from lower-yield to higher-yield strategy
        StrategyAllocation storage fromAlloc = allocations[token][currentStrategy];
        uint256 rebalanceAmount = fromAlloc.principal / 2;///Move 50% (configurable)
        
        if (rebalanceAmount == 0) return;
        bytes memory fromAuxData = strategyAuxData[token][currentStrategy];
        uint256 shares = _calculateShares(token, currentStrategy, rebalanceAmount);
        uint256 withdrawn = strategies[currentStrategy].withdraw(token, shares, fromAuxData);
        
       ///Deposit to best strategy
        bytes memory toAuxData = strategyAuxData[token][bestStrategy];
        SafeTransferLib.safeApprove(token, address(strategies[bestStrategy]), withdrawn);
        strategies[bestStrategy].deposit(token, withdrawn, toAuxData);

        unchecked {
            fromAlloc.principal -= uint128(rebalanceAmount);
            allocations[token][bestStrategy].principal += uint128(withdrawn);
            tokenAlloc.lastYieldCheck = uint128(block.timestamp);
        }
        
        emit FundsRebalanced(token, currentStrategy, bestStrategy, rebalanceAmount);
    }
    
    /// @notice Smart compound: harvest and reinvest in highest-yielding strategy
    function smartCompound(address token) external onlyOwner nonReentrant {
       ///Harvest from all strategies
        uint256 totalHarvested = 0;
        for (uint8 i = 1; i <= 10; i++) {///Support up to 10 strategies
            if (address(strategies[i]) == address(0)) continue;
            
            StrategyAllocation storage alloc = allocations[token][i];
            if (alloc.principal == 0) continue;
            
            bytes memory auxData = strategyAuxData[token][i];
            uint256 harvested = strategies[i].harvest(token, auxData);
            totalHarvested += harvested;
        }
        if (totalHarvested < autoCompoundThresholdBps) return;///Too small to compound
       ///Find best strategy
        (uint8 bestStrategy, ) = _getBestStrategy(token);
        if (bestStrategy == 0) return;
       ///Reinvest in best strategy
        bytes memory auxData = strategyAuxData[token][bestStrategy];
        SafeTransferLib.safeApprove(token, address(strategies[bestStrategy]), totalHarvested);
        strategies[bestStrategy].deposit(token, totalHarvested, auxData);
        unchecked {
            allocations[token][bestStrategy].principal += uint128(totalHarvested);
        }
        
        emit YieldCompounded(token, bestStrategy, totalHarvested);
    }
    
    /// @notice Get best strategy for a token based on APY
    function getBestStrategy(address token) external view returns (uint8 strategyId, uint256 apyBps) {
        return _getBestStrategy(token);
    }
    
    /// @notice Get total value across all strategies
    function getTotalValue(address token) external view returns (uint256 total) {
        for (uint8 i = 1; i <= 10; i++) {
            if (address(strategies[i]) == address(0)) continue;
            bytes memory auxData = strategyAuxData[token][i];
            total += strategies[i].getBalance(token, auxData);
        }
    }
    
    function _getBestStrategy(address token) internal view returns (uint8 bestStrategy, uint256 bestAPY) {
        for (uint8 i = 1; i <= 10; i++) {
            if (address(strategies[i]) == address(0)) continue;
            bytes memory auxData = strategyAuxData[token][i];
            if (!strategies[i].supportsToken(token, auxData)) continue;
            uint256 apy = _getStrategyAPY(token, i);
            if (apy > bestAPY) {
                bestAPY = apy;
                bestStrategy = i;
            }
        }
    }
    
    function _getStrategyAPY(address token, uint8 strategyId) internal view returns (uint256 apyBps) {
        bytes memory auxData = strategyAuxData[token][strategyId];
        return strategies[strategyId].getAPY(token, auxData);
    }
    
    function _getLargestAllocation(address token) internal view returns (uint8 largestStrategy) {
        uint128 largestAmount = 0;
        for (uint8 i = 1; i <= 10; i++) {
            StrategyAllocation storage alloc = allocations[token][i];
            if (alloc.principal > largestAmount) {
                largestAmount = alloc.principal;
                largestStrategy = i;
            }
        }
    }
    
    function _calculateShares(address token, uint8 strategyId, uint256 amount) internal view returns (uint256) {
       ///Simplified: assume 1:1 for now
       ///todo:, calculate based on strategy's share mechanism
        return amount;
    }

    event StrategyRegistered(uint8 indexed strategyId, address indexed strategy);
    event FundsAllocated(uint8 indexed strategyId, address indexed token, uint256 amount);
    event FundsRebalanced(address indexed token, uint8 fromStrategy, uint8 toStrategy, uint256 amount);
    event YieldCompounded(address indexed token, uint8 indexed strategyId, uint256 amount);
    event AllocationUpdated(uint8 indexed strategyId, address indexed token, uint256 oldAlloc, uint256 newAlloc);
    event MaxAllocationUpdated(uint8 indexed strategyId, uint64 oldMax, uint64 newMax);
    event RebalanceThresholdUpdated(uint64 oldThreshold, uint64 newThreshold);
}

