// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title MulticallExample
/// @notice Example implementation of multicall pattern inspired by Sickle
/// @dev Based on Sickle's multicall pattern: https://docs.vfat.io/sickle/

interface IMulticall {
    /// @notice Execute multiple operations atomically
    /// @param calls Array of encoded function calls
    /// @return results Array of return values from each call
    function multicall(bytes[] calldata calls) external returns (bytes[] memory results);
}

/// @title Multicall Implementation Example
contract MulticallExample {
    error MulticallFailed(uint256 index, bytes reason);
    
    /// @notice Execute multiple operations atomically
    /// @param calls Array of encoded function calls (using abi.encodeWithSelector)
    /// @return results Array of return values from each call
    /// @dev All calls execute atomically - if any fails, entire transaction reverts
    /// @dev Example usage:
    ///   bytes[] memory calls = new bytes[](2);
    ///   calls[0] = abi.encodeWithSelector(this.updateYield.selector, token);
    ///   calls[1] = abi.encodeWithSelector(this.harvestAndBridge.selector, token, 50, 0, 0);
    ///   multicall(calls);
    function multicall(bytes[] calldata calls) 
        external 
        returns (bytes[] memory results) 
    {
        results = new bytes[](calls.length);
        
        for (uint256 i = 0; i < calls.length; i++) {
            // Use delegatecall to execute in context of this contract
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            
            if (!success) {
                // Revert with index and reason for debugging
                revert MulticallFailed(i, result);
            }
            
            results[i] = result;
        }
        
        emit MulticallExecuted(calls.length);
    }
    
    /// @notice Alternative: Continue on failure (less safe but more flexible)
    /// @param calls Array of encoded function calls
    /// @param requireSuccess If true, revert on any failure. If false, continue.
    /// @return results Array of return values (empty bytes on failure if requireSuccess=false)
    function multicallWithOptions(
        bytes[] calldata calls,
        bool requireSuccess
    ) external returns (bytes[] memory results, bool[] memory successes) {
        results = new bytes[](calls.length);
        successes = new bool[](calls.length);
        
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            
            if (requireSuccess && !success) {
                revert MulticallFailed(i, result);
            }
            
            successes[i] = success;
            if (success) {
                results[i] = result;
            }
        }
        
        emit MulticallExecuted(calls.length);
    }
    
    event MulticallExecuted(uint256 callCount);
}

/// @title Usage Examples
/// @notice Shows how to use multicall in practice
contract MulticallUsageExamples {
    
    /// @notice Example 1: Update yield and harvest in one transaction
    /// @param vault Vault contract address
    /// @param token Token address
    function exampleUpdateAndHarvest(address vault, address token) external {
        bytes[] memory calls = new bytes[](2);
        
        // Call 1: Update yield
        calls[0] = abi.encodeWithSignature(
            "updateYield(address)",
            token
        );
        
        // Call 2: Harvest and bridge (50% compound, 50% bridge)
        calls[1] = abi.encodeWithSignature(
            "harvestAndBridge(address,uint8,uint64,uint256)",
            token,
            50,  // compoundPercent
            0,   // customSlippageBps (use default)
            0    // minBridgeAmount (calculate from slippage)
        );
        
        // Execute both atomically
        IMulticall(vault).multicall(calls);
    }
    
    /// @notice Example 2: Zap into Slipstream and stake in one transaction
    /// @param vault Vault contract address
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amount Amount to zap
    function exampleZapAndStake(
        address vault,
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external {
        bytes[] memory calls = new bytes[](1);
        
        // Zap into Slipstream position (includes staking if stakeInGauge=true)
        calls[0] = abi.encodeWithSignature(
            "zapIntoSlipstreamPosition(address,address,uint256,uint24,int24,int24,uint256,uint256,bool)",
            tokenIn,
            tokenOut,
            amount,
            100,      // fee (0.01%)
            -887220,  // tickLower (full range)
            887220,   // tickUpper (full range)
            0,        // minAmount0
            0,        // minAmount1
            true      // stakeInGauge
        );
        
        IMulticall(vault).multicall(calls);
    }
    
    /// @notice Example 2b: Collect Slipstream fees AND harvest rewards in one transaction
    /// @param vault Vault contract address
    /// @param tokenId NFT token ID
    /// @param token0 Token0 address
    /// @param token1 Token1 address
    /// @param fee Fee tier
    function exampleCollectFeesAndHarvest(
        address vault,
        uint256 tokenId,
        address token0,
        address token1,
        uint24 fee
    ) external {
        bytes[] memory calls = new bytes[](1);
        
        // Optimized: Single call combines both operations
        calls[0] = abi.encodeWithSignature(
            "collectFeesAndHarvestRewards(uint256,address,address,uint24)",
            tokenId,
            token0,
            token1,
            fee
        );
        
        IMulticall(vault).multicall(calls);
    }
    
    /// @notice Example 2c: Full yield cycle - Harvest → Zap → Stake in one transaction
    /// @param vault Vault contract address
    /// @param token Token to harvest yield from
    /// @param compoundPercent Percentage to compound (50 = 50% compound, 50% bridge)
    /// @param zapAmount Amount to zap into Slipstream
    /// @param tokenOut Output token for Slipstream pair
    /// @param fee Fee tier
    function exampleFullYieldCycle(
        address vault,
        address token,
        uint8 compoundPercent,
        uint256 zapAmount,
        address tokenOut,
        uint24 fee
    ) external {
        bytes[] memory calls = new bytes[](1);
        
        // Ultimate efficiency: All operations in one call!
        // Note: This requires the fullYieldCycleZapIntoSlipstream function
        // For now, use separate calls:
        calls = new bytes[](3);
        
        // Step 1: Update yield
        calls[0] = abi.encodeWithSignature("updateYield(address)", token);
        
        // Step 2: Harvest and bridge
        calls[1] = abi.encodeWithSignature(
            "harvestAndBridge(address,uint8,uint64,uint256)",
            token,
            compoundPercent,
            0,   // customSlippageBps
            0    // minBridgeAmount
        );
        
        // Step 3: Zap into Slipstream position
        calls[2] = abi.encodeWithSignature(
            "zapIntoSlipstreamPosition(address,address,uint256,uint24,int24,int24,uint256,uint256,bool)",
            token,
            tokenOut,
            zapAmount,
            fee,
            -887220,  // tickLower
            887220,   // tickUpper
            0,        // minAmount0
            0,        // minAmount1
            true      // stakeInGauge
        );
        
        IMulticall(vault).multicall(calls);
    }
    
    /// @notice Example 3: Complex workflow - Deposit, Zap, Harvest
    /// @param vault Vault contract address
    /// @param token Token address
    /// @param amount Amount to deposit
    function exampleComplexWorkflow(
        address vault,
        address token,
        uint256 amount
    ) external {
        bytes[] memory calls = new bytes[](3);
        
        // Step 1: Deposit available funds
        calls[0] = abi.encodeWithSignature(
            "depositAvailable(address,bool)",
            token,
            false  // useSmartAllocation
        );
        
        // Step 2: Update yield
        calls[1] = abi.encodeWithSignature(
            "updateYield(address)",
            token
        );
        
        // Step 3: Harvest if yield available
        calls[2] = abi.encodeWithSignature(
            "harvestAndBridge(address,uint8,uint64,uint256)",
            token,
            50,  // compoundPercent
            0,   // customSlippageBps
            0    // minBridgeAmount
        );
        
        IMulticall(vault).multicall(calls);
    }
    
    /// @notice Example 4: Batch operations on multiple tokens
    /// @param vault Vault contract address
    /// @param tokens Array of token addresses
    function exampleBatchUpdateYield(
        address vault,
        address[] calldata tokens
    ) external {
        bytes[] memory calls = new bytes[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            calls[i] = abi.encodeWithSignature(
                "updateYield(address)",
                tokens[i]
            );
        }
        
        IMulticall(vault).multicall(calls);
    }
}

/// @title Gas Comparison
/// @notice Shows gas savings from multicall
contract GasComparison {
    
    /// @notice Without multicall: 3 separate transactions
    /// Gas: ~150k + ~200k + ~180k = ~530k gas
    function withoutMulticall(address vault, address token) external {
        // Tx 1: Update yield (~150k gas)
        // Tx 2: Harvest (~200k gas)  
        // Tx 3: Deposit (~180k gas)
        // Total: ~530k gas + 3x base transaction cost (~21k each = 63k)
        // Grand Total: ~593k gas
    }
    
    /// @notice With multicall: 1 transaction
    /// Gas: ~500k gas (saves ~93k gas + 2x base tx cost = ~147k total savings)
    function withMulticall(address vault, address token) external {
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("updateYield(address)", token);
        calls[1] = abi.encodeWithSignature("harvestAndBridge(address,uint8,uint64,uint256)", token, 50, 0, 0);
        calls[2] = abi.encodeWithSignature("depositAvailable(address,bool)", token, false);
        
        IMulticall(vault).multicall(calls);
        // Total: ~500k gas + 1x base transaction cost (~21k)
        // Grand Total: ~521k gas
        // Savings: ~72k gas (12% reduction)
    }
}


