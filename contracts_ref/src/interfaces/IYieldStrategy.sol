// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IYieldStrategy
/// @notice Interface for extensible yield strategies
/// @dev All strategies must implement this interface for the allocator to work
interface IYieldStrategy {
    /// @notice Get the strategy ID (unique identifier)
    function strategyId() external pure returns (uint8);
    
    /// @notice Get the strategy name
    function strategyName() external pure returns (string memory);
    
    /// @notice Deposit tokens into the strategy
    /// @param token Token address to deposit
    /// @param amount Amount to deposit
    /// @param auxData Additional data (e.g., pair token for Velodrome)
    /// @return shares Amount of shares/position received
    function deposit(address token, uint256 amount, bytes calldata auxData) external returns (uint256 shares);
    
    /// @notice Withdraw tokens from the strategy
    /// @param token Token address to withdraw
    /// @param shares Amount of shares/position to withdraw
    /// @param auxData Additional data
    /// @return amount Amount of tokens received
    function withdraw(address token, uint256 shares, bytes calldata auxData) external returns (uint256 amount);
    
    /// @notice Get current balance/value in the strategy
    /// @param token Token address
    /// @param auxData Additional data
    /// @return balance Current value in tokens
    function getBalance(address token, bytes calldata auxData) external view returns (uint256 balance);
    
    /// @notice Get available yield (harvestable amount)
    /// @param token Token address
    /// @param auxData Additional data
    /// @return yield Available yield in tokens
    function getAvailableYield(address token, bytes calldata auxData) external view returns (uint256 yield);
    
    /// @notice Harvest yield from the strategy
    /// @param token Token address
    /// @param auxData Additional data
    /// @return harvested Amount of yield harvested
    function harvest(address token, bytes calldata auxData) external returns (uint256 harvested);
    
    /// @notice Get current APY (Annual Percentage Yield) in basis points
    /// @param token Token address
    /// @param auxData Additional data
    /// @return apyBps APY in basis points (e.g., 500 = 5%)
    function getAPY(address token, bytes calldata auxData) external view returns (uint256 apyBps);
    
    /// @notice Check if strategy supports a token
    /// @param token Token address
    /// @param auxData Additional data
    /// @return supported True if token is supported
    function supportsToken(address token, bytes calldata auxData) external view returns (bool supported);
}

