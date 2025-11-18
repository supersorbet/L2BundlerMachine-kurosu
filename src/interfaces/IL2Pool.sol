// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Tydro L2Pool interface (compressed calldata for Ink L2)
/// @dev Uses bytes32 encoded arguments instead of standard Aave V3 interface
interface IL2Pool {
    /// @notice Supply assets to the protocol
    /// @param args Encoded parameters: assetId (16 bits) + shortenedAmount (128 bits) + referralCode (16 bits)
    function supply(bytes32 args) external;

    /// @notice Withdraw assets from the protocol
    /// @param args Encoded parameters: assetId (16 bits) + shortenedAmount (128 bits)
    /// @return The amount withdrawn
    function withdraw(bytes32 args) external returns (uint256);

    /// @notice Get reserve data (same as IPool)
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );
}

/// @notice Helper library to encode L2Pool arguments
library L2PoolEncoder {
    /// @notice Encode supply arguments
    /// @param assetId The asset ID (uint16)
    /// @param amount The amount to supply (will be shortened to 128 bits)
    /// @param referralCode The referral code (uint16)
    /// @return Encoded bytes32 arguments
    function encodeSupply(uint16 assetId, uint256 amount, uint16 referralCode) internal pure returns (bytes32) {
        // Pack: assetId (bits 0-15) + shortenedAmount (bits 16-143) + referralCode (bits 144-159)
        // shortenedAmount = amount / 1e10 (to fit in 128 bits while preserving precision)
        uint128 shortenedAmount = uint128(amount / 1e10);
        return bytes32(
            uint256(assetId) |
            (uint256(shortenedAmount) << 16) |
            (uint256(referralCode) << 144)
        );
    }

    /// @notice Encode withdraw arguments
    /// @param assetId The asset ID (uint16)
    /// @param amount The amount to withdraw (will be shortened to 128 bits, or use type(uint256).max for full withdrawal)
    /// @return Encoded bytes32 arguments
    function encodeWithdraw(uint16 assetId, uint256 amount) internal pure returns (bytes32) {
        // Pack: assetId (bits 0-15) + shortenedAmount (bits 16-143)
        uint128 shortenedAmount;
        if (amount == type(uint256).max) {
            shortenedAmount = type(uint128).max; // Max value for full withdrawal
        } else {
            shortenedAmount = uint128(amount / 1e10);
        }
        return bytes32(
            uint256(assetId) |
            (uint256(shortenedAmount) << 16)
        );
    }
}

