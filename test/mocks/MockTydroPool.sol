// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {MockAToken} from "./MockAToken.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title MockTydroPool
/// @notice Mock AAVE V3-style pool that simulates yield over time with compressed calldata interface
contract MockTydroPool is ERC20 {
    using SafeTransferLib for address;

    /// @notice Annual yield rate (in BPS, e.g., 300 = 3% APY)
    uint256 public annualYieldBps = 300;

    /// @notice Track deposits per underlying token (aggregated for simplicity)
    mapping(address => uint256) public deposits;

    /// @notice Track last deposit timestamp per token
    mapping(address => uint256) public lastDepositTime;

    /// @notice aToken for each underlying token
    mapping(address => address) public aTokens;

    /// @notice Asset ID mappings to emulate L2 compressed calldata expectations
    mapping(address => uint16) public tokenToAssetId;
    mapping(uint16 => address) public assetIdToToken;

    constructor() ERC20("Mock Tydro Pool", "MTYDRO") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @notice Configure an asset/token pair with a mock asset ID (mirrors Tydro config)
    function setTokenConfig(address token, uint16 assetId) external {
        tokenToAssetId[token] = assetId;
        assetIdToToken[assetId] = token;
        _ensureAToken(token);
    }

    /// @notice Deploy aToken if needed
    function _ensureAToken(address token) internal {
        if (aTokens[token] == address(0)) {
            MockAToken aToken = new MockAToken(token, address(this));
            aTokens[token] = address(aToken);
        }
    }

    /// @notice Supply via compressed calldata (matches IL2Pool interface)
    function supply(bytes32 args) external returns (uint256) {
        (address token, uint256 amount) = _decodeSupply(args);
        require(token != address(0), "Asset not configured");
        return _supply(token, amount, msg.sender);
    }

    /// @notice Withdraw via compressed calldata (matches IL2Pool interface)
    function withdraw(bytes32 args) external returns (uint256) {
        (address token, uint256 amount) = _decodeWithdraw(args);
        require(token != address(0), "Asset not configured");
        return _withdraw(token, amount, msg.sender);
    }

    /// @notice Legacy helper used by tests
    function deposit(address token, uint256 amount) external returns (uint256) {
        return _supply(token, amount, msg.sender);
    }

    /// @notice Legacy helper used by tests
    function withdraw(address token, uint256 amount) public returns (uint256) {
        return _withdraw(token, amount, msg.sender);
    }

    function _supply(address token, uint256 amount, address onBehalfOf) internal returns (uint256) {
        token.safeTransferFrom(msg.sender, address(this), amount);

        _ensureAToken(token);
        deposits[token] += amount;
        lastDepositTime[token] = block.timestamp;

        // Mint aTokens 1:1
        MockAToken(aTokens[token]).mint(onBehalfOf, amount);

        return amount;
    }

    function _withdraw(address token, uint256 amount, address to) internal returns (uint256) {
        address aToken = aTokens[token];
        require(aToken != address(0), "Token not deployed");

        uint256 principal = deposits[token];
        uint256 currentBalance = _getCurrentBalance(token);
        require(currentBalance > 0, "No liquidity");

        if (amount == type(uint256).max || amount > currentBalance) amount = currentBalance;

        // Calculate proportional aToken burn based on principal share
        uint256 burnAmount = principal == 0 ? 0 : (amount * principal) / currentBalance;

        // Burn aTokens from user up to their balance
        uint256 userATokenBalance = MockAToken(aToken).rawBalanceOf(to);
        if (burnAmount > userATokenBalance) {
            burnAmount = userATokenBalance;
        }
        if (burnAmount > 0) {
            MockAToken(aToken).burn(to, burnAmount);
        }

        // Ensure pool has enough liquidity (tests can simulate refills)
        uint256 poolBalance = ERC20(token).balanceOf(address(this));
        if (amount > poolBalance) {
            MockERC20(token).mint(address(this), amount - poolBalance);
        }

        // Transfer underlying tokens to user
        token.safeTransfer(to, amount);

        // Update principal (reduce by the portion corresponding to burn)
        if (burnAmount >= principal) {
            deposits[token] = 0;
        } else if (principal > 0) {
            uint256 principalReduction = burnAmount;
            if (principalReduction > principal) principalReduction = principal;
            deposits[token] = principal - principalReduction;
        }

        return amount;
    }

    function _decodeSupply(bytes32 args) internal view returns (address token, uint256 amount) {
        uint256 raw = uint256(args);
        uint16 assetId = uint16(raw);
        token = assetIdToToken[assetId];
        require(token != address(0), "Unregistered asset");
        amount = (raw >> 16) & ((uint256(1) << 128) - 1);
    }

    function _decodeWithdraw(bytes32 args) internal view returns (address token, uint256 amount) {
        uint256 raw = uint256(args);
        uint16 assetId = uint16(raw);
        token = assetIdToToken[assetId];
        require(token != address(0), "Unregistered asset");
        uint256 rawAmount = (raw >> 16) & ((uint256(1) << 128) - 1);
        if (rawAmount == type(uint128).max) {
            amount = type(uint256).max;
        } else {
            amount = rawAmount;
        }
    }

    /// @notice Get current balance with yield accrued
    function _getCurrentBalance(address token) internal view returns (uint256) {
        uint256 principal = deposits[token];
        if (principal == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastDepositTime[token];
        if (timeElapsed == 0) return principal;

        // Calculate yield: principal * (annualYield / seconds per year) * timeElapsed
        uint256 yield = (principal * annualYieldBps * timeElapsed) / (10000 * 365 days);

        return principal + yield;
    }

    /// @notice Get reserve data (for aToken address lookup)
    function getReserveData(address asset) external view returns (
        uint256,
        uint128,
        uint128,
        uint128,
        uint128,
        uint128,
        uint40,
        uint16,
        address aTokenAddress,
        address,
        address,
        address,
        uint128,
        uint128,
        uint128
    ) {
        return (
            0, 0, 0, 0, 0, 0, 0,
            tokenToAssetId[asset],
            aTokens[asset],
            address(0), address(0), address(0),
            0, 0, 0
        );
    }

    /// @notice Balance of underlying in pool (override ERC20, but return deposits)
    function balanceOf(address account) public view override returns (uint256) {
        return deposits[account];
    }
}

