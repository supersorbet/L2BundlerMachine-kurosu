// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Standard Bridge interface for Optimism/Base/Ink L2s
/// @dev This is the L2StandardBridge that exists on all OP Stack chains
interface IL2StandardBridge {
    /// @notice Withdraws tokens to L1
    /// @param _l2Token Address of token on L2
    /// @param _to Recipient on L1
    /// @param _amount Amount to bridge
    /// @param _minGasLimit Minimum gas limit for L1 execution
    /// @param _extraData Extra data for the bridge
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

