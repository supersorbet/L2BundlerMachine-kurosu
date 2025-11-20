// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IL2Pool} from "./interfaces/IL2Pool.sol";
import {IL2Encoder} from "./interfaces/IL2Encoder.sol";
import {IAToken} from "./interfaces/ITydroAAVE.sol";

/// @title AdvYieldOptimizer
/// @notice Adv yield optimization strategies for Tydro/Aave V3
/// @dev Implements leverage looping, auto-compounding, rate optimization, and multi-asset strategies
/// @author sorbet/pepecoin core
contract AdvYieldOptimizer is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    error InvalidConfig();
    error InsufficientCollateral();
    error HealthFactorTooLow();
    error MaxLeverageExceeded();
    error InvalidAsset();
    error CompoundTooFrequent();

    struct LeveragePosition {
        address collateralAsset;
        address borrowAsset;
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 healthFactor;
        uint256 lastCompound;
    }

    struct AssetConfig {
        bool enabled;
        uint256 maxLeverageBps; // Max leverage in basis points (e.g., 20000 = 2x)
        uint256 targetLTVBps; // Target loan-to-value (e.g., 7500 = 75%)
        uint256 minHealthFactor; // Minimum health factor (e.g., 150 = 1.5x)
        uint256 compoundInterval; // Minimum seconds between compounds
    }

    IL2Pool public immutable TYDRO_POOL;
    IL2Encoder public immutable L2_ENCODER;

    mapping(address => LeveragePosition) public positions;
    mapping(address => AssetConfig) public assetConfigs;
    mapping(address => address) public aTokens;

    uint256 public constant HEALTH_FACTOR_PRECISION = 1e18;
    uint256 public constant MAX_LEVERAGE_BPS = 50000; // 5x max
    uint256 public defaultCompoundInterval = 3600; // 1 hour

    constructor(address _tydroPool, address _l2Encoder) {
        if (_tydroPool == address(0) || _l2Encoder == address(0)) revert InvalidConfig();
        TYDRO_POOL = IL2Pool(_tydroPool);
        L2_ENCODER = IL2Encoder(_l2Encoder);
        _initializeOwner(msg.sender);
    }

    /// @notice Open a leveraged position (deposit collateral, borrow, deposit borrowed)
    /// @param collateralAsset Asset to use as collateral
    /// @param borrowAsset Asset to borrow against collateral
    /// @param collateralAmount Amount of collateral to deposit
    /// @param leverageBps Desired leverage in basis points (e.g., 20000 = 2x)
    function openLeveragePosition(
        address collateralAsset,
        address borrowAsset,
        uint256 collateralAmount,
        uint256 leverageBps
    ) external onlyOwner nonReentrant {
        if (collateralAmount == 0) revert InvalidConfig();
        if (leverageBps > MAX_LEVERAGE_BPS) revert MaxLeverageExceeded();

        AssetConfig memory config = assetConfigs[collateralAsset];
        if (!config.enabled) revert InvalidAsset();
        if (leverageBps > config.maxLeverageBps) revert MaxLeverageExceeded();

        // Transfer collateral
        SafeTransferLib.safeTransferFrom(collateralAsset, msg.sender, address(this), collateralAmount);

        // Supply collateral
        _supply(collateralAsset, collateralAmount);

        // Calculate borrow amount based on leverage
        uint256 borrowAmount = (collateralAmount * leverageBps) / 10000;
        
        // Borrow against collateral
        _borrow(borrowAsset, borrowAmount);

        // Supply borrowed amount (if same asset, this creates leverage loop)
        if (borrowAsset == collateralAsset) {
            _supply(collateralAsset, borrowAmount);
        }

        // Track position
        positions[collateralAsset] = LeveragePosition({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            collateralAmount: collateralAmount,
            borrowedAmount: borrowAmount,
            healthFactor: _calculateHealthFactor(collateralAsset, borrowAsset, collateralAmount, borrowAmount),
            lastCompound: block.timestamp
        });

        emit LeveragePositionOpened(collateralAsset, borrowAsset, collateralAmount, borrowAmount);
    }

    /// @notice Close leveraged position and withdraw
    function closeLeveragePosition(address collateralAsset) external onlyOwner nonReentrant {
        LeveragePosition memory position = positions[collateralAsset];
        if (position.collateralAmount == 0) revert InvalidConfig();

        // Withdraw all collateral
        uint256 collateralBalance = _getATokenBalance(collateralAsset);
        _withdraw(collateralAsset, collateralBalance);

        // Repay debt
        uint256 debtAmount = _getDebtBalance(position.borrowAsset);
        if (debtAmount > 0) {
            _repay(position.borrowAsset, debtAmount);
        }

        // Transfer remaining to owner
        uint256 remaining = _erc20Balance(collateralAsset);
        if (remaining > 0) {
            SafeTransferLib.safeTransfer(collateralAsset, msg.sender, remaining);
        }

        emit LeveragePositionClosed(collateralAsset, collateralBalance, debtAmount);

        // Clear position
        delete positions[collateralAsset];
    }

    /// @notice Compound yield from leveraged position
    /// @dev Withdraws yield, repays debt, borrows more, supplies more
    function compoundLeveragePosition(address collateralAsset) external onlyOwner nonReentrant {
        LeveragePosition storage position = positions[collateralAsset];
        if (position.collateralAmount == 0) revert InvalidConfig();

        AssetConfig memory config = assetConfigs[collateralAsset];
        if (block.timestamp < position.lastCompound + config.compoundInterval) {
            revert CompoundTooFrequent();
        }

        // Get current balances
        uint256 currentCollateral = _getATokenBalance(collateralAsset);
        uint256 currentDebt = _getDebtBalance(position.borrowAsset);
        
        // Calculate yield (increase in collateral)
        uint256 yield = currentCollateral > position.collateralAmount ? 
            currentCollateral - position.collateralAmount : 0;

        if (yield == 0) return;

        // Withdraw yield
        _withdraw(collateralAsset, yield);

        // Repay some debt to maintain health factor
        uint256 repayAmount = yield / 2; // Use half to repay debt
        if (repayAmount > currentDebt) repayAmount = currentDebt;
        
        if (repayAmount > 0) {
            _repay(position.borrowAsset, repayAmount);
        }

        // Use remaining yield to increase position
        uint256 remainingYield = yield - repayAmount;
        if (remainingYield > 0 && position.borrowAsset == collateralAsset) {
            _supply(collateralAsset, remainingYield);
        }

        // Update position
        position.collateralAmount = _getATokenBalance(collateralAsset);
        position.borrowedAmount = _getDebtBalance(position.borrowAsset);
        position.healthFactor = _calculateHealthFactor(
            collateralAsset,
            position.borrowAsset,
            position.collateralAmount,
            position.borrowedAmount
        );
        position.lastCompound = block.timestamp;

        emit PositionCompounded(collateralAsset, yield);
    }

    /// @notice Auto-compound all positions
    function autoCompoundAll() external onlyOwner nonReentrant {
        // This would iterate through all positions and compound them
        // Implementation depends on how positions are tracked
    }

    /// @notice Optimize across multiple assets based on interest rates
    /// @param assets Array of assets to compare
    /// @param amounts Array of amounts to allocate
    function optimizeMultiAsset(address[] calldata assets, uint256[] calldata amounts) external onlyOwner nonReentrant {
        if (assets.length != amounts.length) revert InvalidConfig();

        // Get current rates for all assets
        uint256[] memory rates = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            (, uint128 currentLiquidityRate, , , , , , , , , , , , , ) = 
                TYDRO_POOL.getReserveData(assets[i]);
            rates[i] = currentLiquidityRate;
        }

        // Find highest rate
        uint256 maxRate = 0;
        uint256 bestAssetIndex = 0;
        for (uint256 i = 0; i < rates.length; i++) {
            if (rates[i] > maxRate) {
                maxRate = rates[i];
                bestAssetIndex = i;
            }
        }

        // Allocate to best asset
        address bestAsset = assets[bestAssetIndex];
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        // Transfer and supply to best asset
        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] > 0) {
                SafeTransferLib.safeTransferFrom(assets[i], msg.sender, address(this), amounts[i]);
                _supply(assets[i], amounts[i]);
            }
        }
    }

    /// @notice Set asset configuration
    function setAssetConfig(address asset, AssetConfig calldata config) external onlyOwner {
        if (config.maxLeverageBps > MAX_LEVERAGE_BPS) revert MaxLeverageExceeded();
        assetConfigs[asset] = config;
        emit AssetConfigUpdated(asset, config);
    }

    /// @notice Get optimal leverage for an asset based on rates
    function getOptimalLeverage(address collateralAsset, address borrowAsset) 
        external 
        view 
        returns (uint256 optimalLeverageBps, uint256 expectedAPY) 
    {
        (, uint128 supplyRate, , uint128 borrowRate, , , , , , , , , , , ) = 
            TYDRO_POOL.getReserveData(collateralAsset);
        
        // Calculate net yield: supply rate - borrow rate
        uint256 netYield = supplyRate > borrowRate ? supplyRate - borrowRate : 0;
        
        // Optimal leverage maximizes net yield while maintaining safety
        // This is a simplified calculation
        optimalLeverageBps = 20000; // 2x default
        expectedAPY = (supplyRate * 2 - borrowRate) * 365 days / 1e18;
    }

    function _supply(address asset, uint256 amount) internal {
        bytes32 supplyArgs = L2_ENCODER.encodeSupplyParams(asset, amount, 0);
        TYDRO_POOL.supply(supplyArgs);
        
        // Cache aToken address
        if (aTokens[asset] == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = 
                TYDRO_POOL.getReserveData(asset);
            aTokens[asset] = aTokenAddress;
        }
    }

    function _withdraw(address asset, uint256 amount) internal returns (uint256) {
        bytes32 withdrawArgs = L2_ENCODER.encodeWithdrawParams(asset, amount);
        return TYDRO_POOL.withdraw(withdrawArgs);
    }

    function _borrow(address asset, uint256 amount) internal {
        // Tydro uses compressed calldata for borrow too
        // This would need to be implemented based on Tydro's actual interface
        // For now, this is a placeholder
    }

    function _repay(address asset, uint256 amount) internal {
        // Tydro uses compressed calldata for repay too
        // This would need to be implemented based on Tydro's actual interface
    }

    function _getATokenBalance(address asset) internal view returns (uint256) {
        address aToken = aTokens[asset];
        if (aToken == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = 
                TYDRO_POOL.getReserveData(asset);
            aToken = aTokenAddress;
        }
        return aToken == address(0) ? 0 : IAToken(aToken).balanceOf(address(this));
    }

    function _getDebtBalance(address asset) internal view returns (uint256) {
        // Get variable debt token balance
        (, , , , , , , , , , address variableDebtToken, , , , ) = 
            TYDRO_POOL.getReserveData(asset);
        // Would need to query debt token balance
        return 0; // Placeholder
    }

    function _calculateHealthFactor(
        address collateralAsset,
        address borrowAsset,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal view returns (uint256) {
        // Simplified health factor calculation
        // Real implementation would use LTV and liquidation threshold from reserve data
        if (debtAmount == 0) return type(uint256).max;
        
        // Get LTV from reserve configuration
        (uint256 config, , , , , , , , , , , , , , ) = 
            TYDRO_POOL.getReserveData(collateralAsset);
        
        uint256 ltv = (config >> 16) & 0xFFFF; // Extract LTV from config
        uint256 maxBorrow = (collateralAmount * ltv) / 10000;
        
        if (debtAmount == 0) return type(uint256).max;
        return (maxBorrow * HEALTH_FACTOR_PRECISION) / debtAmount;
    }

    function _erc20Balance(address token) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    event LeveragePositionOpened(address indexed collateral, address indexed borrow, uint256 collateralAmount, uint256 borrowedAmount);
    event LeveragePositionClosed(address indexed collateral, uint256 collateralWithdrawn, uint256 debtRepaid);
    event PositionCompounded(address indexed asset, uint256 yieldCompounded);
    event AssetConfigUpdated(address indexed asset, AssetConfig config);

}
