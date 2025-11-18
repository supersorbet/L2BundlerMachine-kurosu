// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Interface for the Tydro L2 compressed calldata encoder
interface IL2Encoder {
    /// @notice Encode supply parameters for L2Pool.supply
    /// @param asset Underlying asset address
    /// @param amount Raw amount (no scaling)
    /// @param referralCode Referral code (usually 0)
    /// @return args Packed bytes32 calldata for L2Pool.supply
    function encodeSupplyParams(address asset, uint256 amount, uint16 referralCode) external view returns (bytes32 args);

    /// @notice Encode withdraw parameters for L2Pool.withdraw
    /// @param asset Underlying asset address
    /// @param amount Amount to withdraw (use type(uint256).max for full withdrawal)
    /// @return args Packed bytes32 calldata for L2Pool.withdraw
    function encodeWithdrawParams(address asset, uint256 amount) external view returns (bytes32 args);
}
