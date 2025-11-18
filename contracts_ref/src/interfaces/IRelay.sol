// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Relay Depository interface - where users deposit funds on origin chain
/// @dev Based on Relay Protocol documentation: https://docs.relay.link/references/protocol/overview
interface IRelayDepository {
    /// @notice Deposit tokens to initiate a cross-chain transfer
    /// @param destinationChainId Destination chain ID
    /// @param recipient Recipient address on destination chain
    /// @param token Token address
    /// @param amount Amount to bridge
    /// @param maxFee Maximum fee willing to pay
    /// @param deadline Deadline for the deposit
    /// @return depositId Unique identifier for this deposit
    function deposit(
        uint256 destinationChainId,
        address recipient,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint256 deadline
    ) external returns (bytes32 depositId);
}

/// @notice Relay Hub interface - tracks deposits and fills
/// @dev Hub keeps track of deposits and allows relayers to settle
interface IRelayHub {
    /// @notice Get deposit information
    /// @param depositId Deposit identifier
    /// @return destinationChainId Destination chain ID
    /// @return recipient Recipient address
    /// @return token Token address
    /// @return amount Amount deposited
    /// @return filled Whether the deposit has been filled
    function getDeposit(bytes32 depositId)
        external
        view
        returns (
            uint256 destinationChainId,
            address recipient,
            address token,
            uint256 amount,
            bool filled
        );
    
    /// @notice Mark a deposit as filled (called by relayer after filling)
    /// @param depositId Deposit identifier
    function markFilled(bytes32 depositId) external;
    
    /// @notice Settle a filled deposit to claim payment
    /// @param depositId Deposit identifier
    function settle(bytes32 depositId) external;
}

/// @notice Relay Oracle interface - verifies fills
/// @dev Oracle verifies that intents were correctly filled
interface IRelayOracle {
    /// @notice Verify that a deposit was correctly filled on destination chain
    /// @param depositId Deposit identifier
    /// @param destinationChainId Destination chain ID
    /// @param recipient Recipient address
    /// @param token Token address
    /// @param amount Amount that should have been filled
    /// @return verified Whether the fill is verified
    function verifyFill(
        bytes32 depositId,
        uint256 destinationChainId,
        address recipient,
        address token,
        uint256 amount
    ) external view returns (bool verified);
}

