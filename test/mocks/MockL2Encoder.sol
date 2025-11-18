// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IL2Encoder} from "../../src/interfaces/IL2Encoder.sol";

/// @notice Mock encoder that mirrors Tydro's on-chain L2Encoder bit packing
contract MockL2Encoder is IL2Encoder {
    mapping(address => uint16) public assetIds;

    function setAssetId(address asset, uint16 assetId) external {
        assetIds[asset] = assetId;
    }

    function encodeSupplyParams(address asset, uint256 amount, uint16 referralCode) external view returns (bytes32 args) {
        uint16 assetId = assetIds[asset];
        require(assetId != 0 || asset == address(0), "assetId not set");
        args = bytes32(
            uint256(assetId)
            | (uint256(amount) << 16)
            | (uint256(referralCode) << 144)
        );
    }

    function encodeWithdrawParams(address asset, uint256 amount) external view returns (bytes32 args) {
        uint16 assetId = assetIds[asset];
        require(assetId != 0 || asset == address(0), "assetId not set");
        uint256 packedAmount = amount >= type(uint128).max ? type(uint128).max : amount;
        args = bytes32(
            uint256(assetId)
            | (packedAmount << 16)
        );
    }
}

