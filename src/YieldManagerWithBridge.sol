// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IRelayDepository} from "./interfaces/IRelay.sol";
import {IL2Pool} from "./interfaces/IL2Pool.sol";
import {IL2Encoder} from "./interfaces/IL2Encoder.sol";
import {IAToken} from "./interfaces/ITydroAAVE.sol";
import {IVeloPair, IVeloRouter} from "./interfaces/IVelodrome.sol";

/// @title YieldManagerWithBridge
/// @notice Manages yield across Tydro and Velodrome, with Relay Protocol bridge integration
/// @dev Uses Relay Protocol for L1 transfers (https://docs.relay.link)
/// @author sorbet/pepecoin core
contract YieldManagerWithBridge is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @dev Error for invalid address
    error InvalidAddress();
    /// @dev Error for invalid amount
    error InvalidAmount();
    /// @dev Error for invalid strategy
    error InvalidStrategy();
    /// @dev Error for no yield
    error NoYield();
    error PairNotFound();
    error NotDeployedToTydro();
    error InvalidFee();

    /// @dev Relay Depository on L2 (Ink) - where we deposit to bridge to L1
    address public immutable RELAY_DEPOSITORY;
    /// @dev L1 chain ID (Ethereum mainnet)
    uint256 public constant L1_CHAIN_ID = 1;
    /// @dev Tydro lending pool (AAVE V3 fork)
    address public immutable TYDRO_POOL;
    /// @dev L2 encoder contract (compressed calldata helper)
    address public immutable L2_ENCODER;
    /// @dev Velodrome router
    address public immutable VELO_ROUTER;
    /// @dev L1 recipient address
    address public l1Recipient;
    /// @dev Maximum fee willing to pay for bridging (in basis points or absolute)
    uint256 public maxBridgeFee;

    /// @dev Strategy tracking - packed for gas efficiency
    struct Position {
        uint128 principal;
        uint32 lastHarvest;///Truncated timestamp
    }

    /// @dev token => strategy => position (1 = Tydro, 2 = Velodrome)
    mapping(address => mapping(uint256 => Position)) private _positions;
    /// @dev token => aToken address
    mapping(address => address) private _aTokens;
    /// @dev pairHash => LP amount
    mapping(bytes32 => uint256) private _veloLP;
    /// @dev pairHash => pair address
    mapping(bytes32 => address) private _veloPairs;

    /// @param _relayDepository Address of Relay Depository on Ink L2
    /// @param _tydroPool Address of Tydro lending pool
    /// @param _l2Encoder Address of L2 encoder helper
    /// @param _veloRouter Address of Velodrome router
    /// @param _l1Recipient Initial L1 recipient address
    constructor(
        address _relayDepository,
        address _tydroPool,
        address _l2Encoder,
        address _veloRouter,
        address _l1Recipient
    ) {
        if (_relayDepository == address(0)) revert InvalidAddress();
        if (_tydroPool == address(0)) revert InvalidAddress();
        if (_l2Encoder == address(0)) revert InvalidAddress();
        if (_veloRouter == address(0)) revert InvalidAddress();
        if (_l1Recipient == address(0)) revert InvalidAddress();

        RELAY_DEPOSITORY = _relayDepository;
        TYDRO_POOL = _tydroPool;
        L2_ENCODER = _l2Encoder;
        VELO_ROUTER = _veloRouter;
        l1Recipient = _l1Recipient;
        maxBridgeFee = 100;///Default 1% fee (100 bps)

        _initializeOwner(msg.sender);
    }

    /// @notice Update L1 recipient address
    function setL1Recipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) revert InvalidAddress();
        address oldRecipient = l1Recipient;
        l1Recipient = _newRecipient;
        emit L1RecipientUpdated(oldRecipient, _newRecipient);
    }

    /// @notice Update maximum bridge fee
    function setMaxBridgeFee(uint256 _maxFee) external onlyOwner {
        if (_maxFee > 10000) revert InvalidFee();///Max 100%
        uint256 oldFee = maxBridgeFee;
        maxBridgeFee = _maxFee;
        emit MaxBridgeFeeUpdated(oldFee, _maxFee);
    }

    /// @notice Bridge tokens to L1 using Relay Protocol
    /// @dev Uses Relay Depository to initiate cross-chain transfer
    /// @dev Relayers will fill the order on L1, then settle to claim payment
    function _bridgeToL1(address token, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();
       ///Calculate max fee (based on amount and maxBridgeFee setting)
        uint256 calculatedMaxFee = (amount * maxBridgeFee) / 10000;
        SafeTransferLib.safeApprove(token, RELAY_DEPOSITORY, amount);
        bytes32 depositId = IRelayDepository(RELAY_DEPOSITORY).deposit(
            L1_CHAIN_ID,          ///Destination chain (L1 Ethereum)
            l1Recipient,          ///Recipient on L1
            token,                ///Token to bridge
            amount,               ///Amount to bridge
            calculatedMaxFee,     ///Maximum fee willing to pay
            block.timestamp + 1 hours///Deadline
        );

        emit DepositInitiated(depositId, token, amount);
        emit BridgedToL1(token, amount, l1Recipient);
    }

    /// @notice Deploy tokens to Tydro lending pool
    function deployToTydro(address token, uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(token, TYDRO_POOL, amount);

        bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(token, amount, 0);
        IL2Pool(TYDRO_POOL).supply(supplyArgs);
       ///Cache aToken address if not already cached
        if (_aTokens[token] == address(0)) {
            _aTokens[token] = _getATokenAddress(token);
        }
        unchecked {
            _positions[token][1].principal += uint128(amount);
            _positions[token][1].lastHarvest = uint32(block.timestamp);
        }

        emit Deployed(1, token, amount);
    }

    /// @notice Harvest yield from Tydro
    function _harvestTydro(address token) internal returns (uint256) {
        address aToken = _aTokens[token];
        if (aToken == address(0)) revert NotDeployedToTydro();
        uint256 aTokenBalance = IAToken(aToken).balanceOf(address(this));
        uint256 principal = _positions[token][1].principal;

        if (aTokenBalance <= principal) return 0;

        uint256 yieldAmount = aTokenBalance - principal;
        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(token, yieldAmount);
        IL2Pool(TYDRO_POOL).withdraw(withdrawArgs);

        unchecked {
            _positions[token][1].lastHarvest = uint32(block.timestamp);
        }

        return yieldAmount;
    }

    /// @notice Get aToken address for an asset
    function _getATokenAddress(address asset) internal view returns (address) {
        (,,,,,,,,address aTokenAddress,,,,,,) = IL2Pool(TYDRO_POOL).getReserveData(asset);
        return aTokenAddress;
    }

    /// @notice Get Tydro balance for a token
    function getTydroBalance(address token) external view returns (uint256) {
        address aToken = _aTokens[token];
        if (aToken == address(0)) return 0;
        return IAToken(aToken).balanceOf(address(this));
    }

    /// @notice Get available yield from Tydro
    function getTydroYield(address token) external view returns (uint256) {
        address aToken = _aTokens[token];
        if (aToken == address(0)) return 0;

        uint256 balance = IAToken(aToken).balanceOf(address(this));
        uint256 principal = _positions[token][1].principal;

        return balance > principal ? balance - principal : 0;
    }

    /// @notice Deploy tokens to Velodrome liquidity pool
    function deployToVelo(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable
    ) external onlyOwner nonReentrant {
        SafeTransferLib.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        SafeTransferLib.safeTransferFrom(tokenB, msg.sender, address(this), amountB);

        SafeTransferLib.safeApprove(tokenA, VELO_ROUTER, amountA);
        SafeTransferLib.safeApprove(tokenB, VELO_ROUTER, amountB);

        (,, uint256 liquidity) = IVeloRouter(VELO_ROUTER).addLiquidity(
            tokenA, tokenB, stable,
            amountA, amountB,
            0, 0,
            address(this),
            block.timestamp
        );

        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);

        unchecked {
            _veloLP[pairHash] += liquidity;
            _positions[tokenA][2].principal += uint128(amountA);
            _positions[tokenA][2].lastHarvest = uint32(block.timestamp);
        }
        _veloPairs[pairHash] = pair;

        emit Deployed(2, tokenA, amountA);
    }

    /// @notice Harvest fees from Velodrome
    function _harvestVelo(address tokenA, address tokenB) internal returns (uint256) {
        uint256 totalFees;
       ///Check both stable and volatile pairs
        for (uint256 i = 0; i < 2;) {
            bool stable = (i == 1);
            bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
            address pair = _veloPairs[pairHash];

            if (pair != address(0)) {
                (uint256 fee0,) = IVeloPair(pair).claimFees();
                totalFees += fee0;
            }

            unchecked {
                ++i;
            }
        }

        if (totalFees > 0) {
            unchecked {
                _positions[tokenA][2].lastHarvest = uint32(block.timestamp);
            }
        }

        return totalFees;
    }

    /// @notice Generate pair hash for Velodrome
    function _pairHash(address tokenA, address tokenB, bool stable) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB, stable));
    }

    /// @notice Get Velodrome LP balance
    function getVeloBalance(address tokenA, address tokenB, bool stable) external view returns (uint256) {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        return _veloLP[pairHash];
    }

    /// @notice Get claimable fees from Velodrome
    function getVeloClaimableFees(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256, uint256) {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = _veloPairs[pairHash];
        if (pair == address(0)) return (0, 0);

        return (
            IVeloPair(pair).claimableFeesToken0(),
            IVeloPair(pair).claimableFeesToken1()
        );
    }

    /// @notice Harvest yield from strategy and auto-split 50/50
    /// @param strategyId 1 = Tydro, 2 = Velodrome
    /// @param token Primary token
    /// @param auxData For Velodrome: abi.encode(tokenB)
    function harvest(
        uint256 strategyId,
        address token,
        bytes calldata auxData
    ) external onlyOwner nonReentrant {
        uint256 yieldAmount;
        if (strategyId == 1) {
            yieldAmount = _harvestTydro(token);
        } else if (strategyId == 2) {
            address tokenB = abi.decode(auxData, (address));
            yieldAmount = _harvestVelo(token, tokenB);
        } else {
            revert InvalidStrategy();
        }
        if (yieldAmount == 0) revert NoYield();
       ///Split 50/50
        uint256 bridgeAmount = yieldAmount / 2;
        uint256 compoundAmount = yieldAmount - bridgeAmount;
       ///1. Bridge 50% to L1
        _bridgeToL1(token, bridgeAmount);
       ///2. Re-deploy 50% to same strategy
        if (strategyId == 1) {
            SafeTransferLib.safeApprove(token, TYDRO_POOL, compoundAmount);
            bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(token, compoundAmount, 0);
            IL2Pool(TYDRO_POOL).supply(supplyArgs);
            unchecked {
                _positions[token][1].principal += uint128(compoundAmount);
            }
        }
       ///todo: compounding needs re-adding liquidity

        emit Harvested(strategyId, token, yieldAmount);
    }

    /// @notice Batch harvest multiple strategies
    function batchHarvest(
        uint256[] calldata strategyIds,
        address[] calldata tokens,
        bytes[] calldata auxData
    ) external onlyOwner nonReentrant {
        uint256 length = strategyIds.length;
        if (length != tokens.length || length != auxData.length) revert();
        for (uint256 i = 0; i < length;) {
            uint256 yieldAmount;
            if (strategyIds[i] == 1) {
                yieldAmount = _harvestTydro(tokens[i]);
            } else if (strategyIds[i] == 2) {
                address tokenB = abi.decode(auxData[i], (address));
                yieldAmount = _harvestVelo(tokens[i], tokenB);
            }
            if (yieldAmount > 0) {
                uint256 bridgeAmount = yieldAmount / 2;
                uint256 compoundAmount = yieldAmount - bridgeAmount;
                _bridgeToL1(tokens[i], bridgeAmount);

                if (strategyIds[i] == 1) {
                    SafeTransferLib.safeApprove(tokens[i], TYDRO_POOL, compoundAmount);
                    bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(tokens[i], compoundAmount, 0);
                    IL2Pool(TYDRO_POOL).supply(supplyArgs);
                    unchecked {
                        _positions[tokens[i]][1].principal += uint128(compoundAmount);
                    }
                }

                emit Harvested(strategyIds[i], tokens[i], yieldAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Withdraw from Tydro
    function withdrawFromTydro(address token, uint256 amount) external onlyOwner nonReentrant {
        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(token, amount);
        uint256 withdrawn = IL2Pool(TYDRO_POOL).withdraw(withdrawArgs);
        SafeTransferLib.safeTransfer(token, msg.sender, withdrawn);
        unchecked {
            _positions[token][1].principal -= uint128(amount);
        }
        emit Withdrawn(1, token, withdrawn);
    }

    /// @notice Withdraw from Velodrome
    function withdrawFromVelo(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external onlyOwner nonReentrant {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = _veloPairs[pairHash];
        if (pair == address(0)) revert PairNotFound();
        SafeTransferLib.safeApprove(pair, VELO_ROUTER, liquidity);

        IVeloRouter(VELO_ROUTER).removeLiquidity(
            tokenA, tokenB, stable,
            liquidity,
            0, 0,
            msg.sender,
            block.timestamp
        );

        unchecked {
            _veloLP[pairHash] -= liquidity;
        }

        emit Withdrawn(2, tokenA, liquidity);
    }

    /// @notice Emergency withdraw any token
    function emsWithdraw(address token) external onlyOwner {
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance > 0) {
            SafeTransferLib.safeTransfer(token, msg.sender, balance);
        }
    }

    event Deployed(uint256 indexed strategyId, address indexed token, uint256 amount);
    event Harvested(uint256 indexed strategyId, address indexed token, uint256 yieldAmount);
    event BridgedToL1(address indexed token, uint256 amount, address indexed l1Recipient);
    event Withdrawn(uint256 indexed strategyId, address indexed token, uint256 amount);
    event L1RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event MaxBridgeFeeUpdated(uint256 oldFee, uint256 newFee);
    event DepositInitiated(bytes32 indexed depositId, address indexed token, uint256 amount);

}

