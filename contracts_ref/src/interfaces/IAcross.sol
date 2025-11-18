// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IHubPool {
    function deposit(
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint256 quoteTimestamp,
        bytes calldata message
    ) external payable;
}

interface ISpokePool {
    /// @notice Legacy deposit function (backwards compatible)
    function deposit(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        uint64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes calldata message,
        uint256 maxCount
    ) external payable;
    
    /// @notice V3 deposit function (newer, recommended)
    /// @dev See: https://docs.across.to/reference/selected-contract-functions
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;
    
    /// @notice Get current time for quote timestamp calculation
    function getCurrentTime() external view returns (uint256);
    
    /// @notice Get quote time buffer
    function depositQuoteTimeBuffer() external view returns (uint32);
    
    /// @notice Get fill deadline buffer
    function fillDeadlineBuffer() external view returns (uint32);
}

