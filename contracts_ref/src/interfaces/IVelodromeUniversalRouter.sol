// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Velodrome Universal Router interface
/// @dev Universal Router uses command encoding via execute function
interface IVelodromeUniversalRouter {
    /// @notice Execute commands with inputs
    /// @param commands Array of command bytes (each command is 1 byte)
    /// @param inputs Array of input data for each command
    /// @dev Commands are encoded as single bytes, inputs are ABI-encoded parameters
    function execute(bytes calldata commands, bytes[] calldata inputs) external payable;
    
    /// @notice Execute batch of commands
    /// @param commands Array of command bytes
    /// @param inputs Array of input data
    function executeBatch(bytes[] calldata commands, bytes[] calldata inputs) external payable;
}

/// @notice Helper library for encoding Velodrome Universal Router commands
/// @dev Based on Velodrome Universal Router: https://github.com/velodrome-finance/universal-router
library VelodromeCommandEncoder {
    // Command structure: f (1 bit) + r (1 bit) + command (6 bits)
    // f = allow revert flag, r = reserved, command = operation ID
    
    // Base command IDs (6 bits, so 0x00-0x3F)
    uint8 constant V2_SWAP_EXACT_IN = 0x00;
    uint8 constant V2_SWAP_EXACT_OUT = 0x01;
    uint8 constant V2_ADD_LIQUIDITY = 0x02;
    uint8 constant V2_REMOVE_LIQUIDITY = 0x03;
    
    /// @notice Encode addLiquidity command with revert flag
    /// @param allowRevert If false, entire tx reverts on failure; if true, continues
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param stable Whether stable pair
    /// @param amountADesired Amount of tokenA
    /// @param amountBDesired Amount of tokenB
    /// @param amountAMin Minimum amount of tokenA
    /// @param amountBMin Minimum amount of tokenB
    /// @param to Recipient address
    /// @param deadline Deadline timestamp
    /// @return command Encoded command byte (f + r + command)
    /// @return input Encoded input data
    function encodeAddLiquidity(
        bool allowRevert,
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) internal pure returns (bytes1 command, bytes memory input) {
        // Encode command: f (bit 7) + r (bit 6, set to 0) + command (bits 0-5)
        uint8 cmdByte = V2_ADD_LIQUIDITY;
        if (allowRevert) {
            cmdByte |= 0x80; // Set bit 7
        }
        command = bytes1(cmdByte);
        
        input = abi.encode(
            tokenA,
            tokenB,
            stable,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }
}

