// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ISpokePool} from "./interfaces/IAcross.sol";
import {IL2Pool} from "./interfaces/IL2Pool.sol";
import {IL2Encoder} from "./interfaces/IL2Encoder.sol";
import {IAToken} from "./interfaces/ITydroAAVE.sol";
import {YieldAllocator} from "./YieldAllocator.sol";
import {IVelodromeHelper} from "./interfaces/IVelodromeHelper.sol";
import {IVeloRouter} from "./interfaces/IVelodrome.sol";
import {VelodromeHelper} from "./VelodromeHelper.sol";
import {ISlipstreamHelper} from "./interfaces/ISlipstreamHelper.sol";
import {ISlipstreamPositionNFT} from "./interfaces/ISlipstream.sol";
import {SlipstreamHelper} from "./SlipstreamHelper.sol";

/// @title BundledYieldVaultV2__MULTICALL
/// @notice (Ink L2) vault for yield farming and bridging yield back to L1 via Across
/// @dev Owner-only operations for private treasury management with comprehensive safety mechanisms
/// @dev Supports multi-strategy allocation via YieldAllocator
/// @dev INCLUDES MULTICALL FUNCTIONALITY (inspired by Sickle pattern)
/// @author sorbet/pepecoin core
/// @notice This is a comparison version showing multicall implementation
contract BundledYieldVaultV2__MULTICALL is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    error TokenNotSupported();
    error L1RecipientNotSet();
    error InsufficientGas();
    error InsufficientYield();
    error DepositFailed();
    error WithdrawFailed();
    error BridgeFailed();
    error InvalidCompoundPercent();
    error InvalidAddress();
    error SlippageTooHigh();
    error InvalidSlippage();
    error InsufficientApproval();
    error InsufficientBalance();
    error AllocatorNotSet();
    error CircuitBreakerActive();
    error RateLimitExceeded();
    error WithdrawalLimitExceeded();
    error InvalidAmount();
    error OperationCooldown();
    error EmsModeInit();
    error DepositLimitExceeded();
    error MulticallFailed(uint256 index, bytes reason);

    /// @dev Tydro pool contract address
    address public immutable TYDRO_POOL;
    /// @dev Across SpokePool contract address
    address public immutable ACROSS_SPOKE_POOL;
    /// @dev L2 encoder contract (compressed calldata helper)
    address public immutable L2_ENCODER;
    /// @dev Velodrome Universal Router address
    address public immutable VELO_ROUTER;
    /// @dev Velodrome Helper contract
    address public immutable VELO_HELPER;
    /// @dev Slipstream Position NFT contract
    address public immutable SLIPSTREAM_POSITION_NFT;
    /// @dev Slipstream Helper contract
    address public immutable SLIPSTREAM_HELPER;

    /// @dev L1 chain ID (Ethereum mainnet)
    uint256 public constant L1_CHAIN_ID = 1;
    /// @dev L1 recipient address (L1Depositor)
    address public l1Recipient;
    /// @dev Mapping from L2 token address to L1 token address
    mapping(address => address) public tokenMapping;

    /// @dev Minimum gas balance required (in wei)
    uint128 public minGasBalance = 0.0069 ether;
    /// @dev Maximum daily withdrawal limit per token (0 = unlimited)
    mapping(address => uint128) public maxDailyWithdrawals;
    /// @dev Maximum deposit limit per token (0 = unlimited)
    mapping(address => uint128) public maxDeposits;
    /// @dev Current day's withdrawn amount per token
    mapping(address => mapping(uint32 => uint128)) public dailyWithdrawals;
    /// @dev Circuit breaker - stops all withdrawals if active
    bool public breakerActive;
    /// @dev Emergency mode - allows only emergency withdrawals
    bool public emergencyMode;

    /// @dev Minimum time between operations per token (anti-spam)
    mapping(address => uint32) public operationCooldown;
    /// @dev Last operation timestamp per token
    mapping(address => uint32) public lastOperationTime;
    /// @dev Maximum operations per hour (0 = unlimited)
    uint8 public maxOperationsPerHour;
    /// @dev Operations count in current hour window
    mapping(uint32 => uint8) public operationsThisHour; ///delete this

    /// @dev Default slippage for bridging (basis points, e.g., 200 = 2%)
    uint64 public defaultSlippageBps = 200;
    /// @dev Auto-refill gas from bridge amount (basis points, e.g., 50 = 0.5%)
    uint64 public autoGasRefillBps = 50;
    /// @dev Default compound percent for auto-harvest (50% = half compound, half bridge)
    uint8 public defaultCompoundPercent = 50;
    /// @dev Minimum yield threshold for auto-harvest (basis points of principal, e.g., 10 = 0.1%)
    uint64 public minYieldThresholdBps = 10;
    /// @dev Pause flag - packed into single storage slot for efficiency
    uint256 private _paused;

    /// @dev Packed struct (4 slots → 1 slot)
    struct TokenStatus {
        uint128 depositedAmount; ///Amount deposited to Tydro
        uint128 currentBalance; ///Current balance in Tydro
        uint128 yieldAvailable; ///Accumulated yield
        uint32 lastUpdate; ///Last update timestamp (block.timestamp truncated)
    }

    /// @dev Parameters for creating a Velodrome LP position
    struct LPParams {
        address tokenA; ///Token A address
        address tokenB; ///Token B address
        uint256 amountA; ///Amount of token A
        uint256 amountB; ///Amount of token B
        bool stable; ///Whether the pair is stable
        bool stakeInGauge;
    }

    struct SlipstreamMintParams {
        address token0; ///Token 0 address
        address token1; ///Token 1 address
        uint24 fee; ///Fee tier (e.g., 100 = 0.01%)
        int24 tickLower; ///Lower tick for the position
        int24 tickUpper; ///Upper tick for the position
        uint256 amount0Desired; ///Amount of token 0 desired
        uint256 amount1Desired; ///Amount of token 1 desired
        uint256 amount0Min; ///Minimum amount of token 0 (for slippage protection)
        uint256 amount1Min; ///Minimum amount of token 1 (for slippage protection)
        uint256 deadline; ///Deadline for the transaction
    }

    struct SlipstreamLiquidityParams {
        uint256 tokenId; ///Token ID
        uint256 amount0Desired; ///Amount of token 0 desired
        uint256 amount1Desired; ///Amount of token 1 desired
        uint256 amount0Min; ///Minimum amount of token 0 (for slippage protection)
        uint256 amount1Min; ///Minimum amount of token 1 (for slippage protection)
        uint256 deadline; ///Deadline for the transaction
    }

    struct SlipstreamDecreaseParams {
        uint256 tokenId; ///Token ID
        uint128 liquidity; ///Liquidity to decrease
        uint256 amount0Min; ///Minimum amount of token 0 (for slippage protection)
        uint256 amount1Min; ///Minimum amount of token 1 (for slippage protection)
        uint256 deadline; ///Deadline for the transaction
    }

    /// @notice Position identifier for batch operations
    struct SlipstreamPositionIdentifier {
        address token0; ///Token 0 address
        address token1; ///Token 1 address
        uint24 fee; ///Fee tier
    }

    /// @notice Parameters for zapping into Slipstream position
    struct ZapSlipstreamParams {
        address tokenOut; ///Output token address (for the pair)
        uint24 fee; ///Fee tier (e.g., 100 = 0.01%)
        int24 tickLower; ///Lower tick for the position
        int24 tickUpper; ///Upper tick for the position
        uint256 minAmount0; ///Minimum amount of token0 (for slippage protection)
        uint256 minAmount1; ///Minimum amount of token1 (for slippage protection)
        bool stakeInGauge; ///If true, stake NFT in LeafCLGauge after minting
    }

    /// @notice Sickle-inspired: Operation type for building multicall arrays
    enum SlipstreamOpType {
        CollectFees,
        HarvestRewards,
        CollectAndHarvest,
        IncreaseLiquidityAndStake,
        DecreaseCollectUnstake
    }

    /// @notice Sickle-inspired: Struct for building multicall operations
    struct SlipstreamMulticallOp {
        SlipstreamOpType opType;
        uint256 tokenId;
        address token0;
        address token1;
        uint24 fee;
        SlipstreamLiquidityParams liqParams;
        SlipstreamDecreaseParams decParams;
    }

    mapping(address => TokenStatus) public tokenStatus;
    /// @dev Cache aToken addresses per underlying token
    mapping(address => address) private _aTokens;
    /// @dev Optional YieldAllocator for smart multi-strategy allocation
    YieldAllocator public yieldAllocator;

    /// @param _tydroPool Tydro pool contract address
    /// @param _l2Encoder L2 encoder contract address
    /// @param _acrossSpokePool Across SpokePool contract address
    /// @param _l1Recipient Initial L1 recipient address
    /// @param _veloRouter Velodrome Universal Router address
    constructor(
        address _tydroPool,
        address _l2Encoder,
        address _acrossSpokePool,
        address _l1Recipient,
        address _veloRouter,
        address _slipstreamPositionNFT
    ) {
        if (
            _tydroPool == address(0) ||
            _acrossSpokePool == address(0) ||
            _l2Encoder == address(0)
        ) revert InvalidAddress();
        if (_l1Recipient == address(0)) revert InvalidAddress();
        if (_veloRouter == address(0) || _slipstreamPositionNFT == address(0))
            revert InvalidAddress();
        TYDRO_POOL = _tydroPool;
        L2_ENCODER = _l2Encoder;
        ACROSS_SPOKE_POOL = _acrossSpokePool;
        VELO_ROUTER = _veloRouter;
        VelodromeHelper helper = new VelodromeHelper(_veloRouter);
        helper.setVault(address(this));
        VELO_HELPER = address(helper);
        SlipstreamHelper slipHelper = new SlipstreamHelper(
            _slipstreamPositionNFT,
            _veloRouter
        );
        slipHelper.setVault(address(this));
        SLIPSTREAM_POSITION_NFT = _slipstreamPositionNFT;
        SLIPSTREAM_HELPER = address(slipHelper);
        l1Recipient = _l1Recipient;

        maxOperationsPerHour = 69; ///? prob remove this
        emergencyMode = false;
        breakerActive = false;

        _initializeOwner(msg.sender);

        emit VaultInitialized(
            _tydroPool,
            _l2Encoder,
            _acrossSpokePool,
            _l1Recipient
        );
        emit VelodromeRouterSet(_veloRouter);
    }

    /// @notice Execute multiple operations atomically in a single transaction
    /// @param calls Array of encoded function calls (use abi.encodeWithSelector)
    /// @return results Array of return values from each call
    /// @dev All calls execute atomically - if any fails, entire transaction reverts
    /// @dev Inspired by vfat's Sickle pattern: https://docs.vfat.io/sickle/
    /// @dev Uses delegatecall to execute in contract context - allows access to storage and state
    /// @dev Gas optimized with assembly for better error handling (Sickle-style)
    /// @dev Example usage:
    ///   bytes[] memory calls = new bytes[](2);
    ///   calls[0] = abi.encodeWithSelector(this.updateYield.selector, token);
    ///   calls[1] = abi.encodeWithSelector(this.harvestAndBridge.selector, token, 50, 0, 0);
    ///   multicall(calls);
    function multicall(
        bytes[] calldata calls
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (bytes[] memory results)
    {
        uint256 length = calls.length;
        results = new bytes[](length);

        ///optimized loop (Sickle pattern)
        for (uint256 i = 0; i < length; ) {
            (bool success, bytes memory result) = address(this).delegatecall(
                calls[i]
            );

            if (!success) {
                ///Bubble up the revert reason
                assembly {
                    ///Copy revert reason from result
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            }

            results[i] = result;
            unchecked {
                ++i;
            }
        }

        emit MulticallExecuted(length);
    }

    /// @notice Execute multiple operations with options (continue on failure)
    /// @param calls Array of encoded function calls
    /// @param requireSuccess If true, revert on any failure. If false, continue.
    /// @return results Array of return values (empty bytes on failure if requireSuccess=false)
    /// @return successes Array indicating which calls succeeded
    /// @dev More flexible than standard multicall - allows partial success
    /// @dev Sickle-inspired pattern for non-atomic operations (use with caution)
    function multicallWithOptions(
        bytes[] calldata calls,
        bool requireSuccess
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (bytes[] memory results, bool[] memory successes)
    {
        uint256 length = calls.length;
        results = new bytes[](length);
        successes = new bool[](length);

        ///optimized loop
        for (uint256 i = 0; i < length; ) {
            (bool success, bytes memory result) = address(this).delegatecall(
                calls[i]
            );

            if (requireSuccess && !success) {
                ///Revert with index and reason for debugging
                revert MulticallFailed(i, result);
            }

            successes[i] = success;
            if (success) {
                results[i] = result;
            }

            ///Unchecked increment for gas savings
            unchecked {
                ++i;
            }
        }

        emit MulticallExecuted(length);
    }

    /// @notice Batch update yield for multiple tokens
    /// @param tokens Array of token addresses to update
    /// @dev More efficient than calling updateYield multiple times
    /// @dev Can be used in multicall for even better gas efficiency
    function batchUpdateYield(
        address[] calldata tokens
    ) external whenNotPaused {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ) {
            _updateYield(tokens[i]);
            unchecked {
                ++i;
            }
        }
        emit BatchYieldUpdated(length);
    }

    /// @notice Sickle-inspired: Pre-built multicall pattern for Slipstream position management
    /// @param tokenId NFT token ID
    /// @param token0 Token0 address
    /// @param token1 Token1 address
    /// @param fee Fee tier
    /// @dev Combines: Collect fees + Harvest rewards in one optimized call
    /// @dev Gas savings: ~30k gas vs separate transactions
    function slipstreamCollectAndHarvest(
        uint256 tokenId,
        address token0,
        address token1,
        uint24 fee
    ) external onlyOwner whenNotPaused nonReentrant {
        ///Use optimized combined function
        this.collectFeesAndHarvestRewards(tokenId, token0, token1, fee);
    }

    /// @notice Sickle-inspired: Pre-built multicall pattern for yield cycle
    /// @param token Token to harvest from
    /// @param compoundPercent Compound percentage (0-100)
    /// @param zapParams Zap parameters for Slipstream
    /// @dev Complete workflow: Update → Harvest → Zap → Stake
    function slipstreamYieldCycle(
        address token,
        uint8 compoundPercent,
        ZapSlipstreamParams calldata zapParams
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        this.fullYieldCycleZapIntoSlipstream(
            token,
            compoundPercent,
            0,
            zapParams
        );
    }

    /// @notice Sickle-inspired: Helper to build multicall array for Slipstream operations
    /// @param operations Array of operation structs
    /// @dev Makes it easy to build complex multicall arrays
    function buildSlipstreamMulticall(
        SlipstreamMulticallOp[] calldata operations
    ) external view returns (bytes[] memory calls) {
        uint256 length = operations.length;
        calls = new bytes[](length);

        for (uint256 i = 0; i < length; ) {
            SlipstreamMulticallOp calldata op = operations[i];

            if (op.opType == SlipstreamOpType.CollectFees) {
                calls[i] = abi.encodeWithSelector(
                    this.collectSlipstreamFees.selector,
                    op.tokenId
                );
            } else if (op.opType == SlipstreamOpType.HarvestRewards) {
                calls[i] = abi.encodeWithSelector(
                    this.harvestSlipstreamRewards.selector,
                    op.token0,
                    op.token1,
                    op.fee
                );
            } else if (op.opType == SlipstreamOpType.CollectAndHarvest) {
                calls[i] = abi.encodeWithSelector(
                    this.collectFeesAndHarvestRewards.selector,
                    op.tokenId,
                    op.token0,
                    op.token1,
                    op.fee
                );
            } else if (
                op.opType == SlipstreamOpType.IncreaseLiquidityAndStake
            ) {
                calls[i] = abi.encodeWithSelector(
                    this.increaseLiquidityAndStake.selector,
                    op.liqParams,
                    op.token0,
                    op.token1,
                    op.fee,
                    true // stake
                );
            } else if (op.opType == SlipstreamOpType.DecreaseCollectUnstake) {
                calls[i] = abi.encodeWithSelector(
                    this.decreaseLiquidityCollectAndUnstake.selector,
                    op.decParams,
                    op.token0,
                    op.token1,
                    op.fee,
                    true // unstake
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch auto-harvest multiple tokens using multicall pattern
    /// @param tokens Array of token addresses
    /// @param compoundPercent Compound percentage for each token (0-100)
    /// @dev Uses multicall internally for atomic execution
    function batchHarvestAndBridge(
        address[] calldata tokens,
        uint8[] calldata compoundPercent
    ) external onlyOwner whenNotPaused nonReentrant {
        if (tokens.length != compoundPercent.length) revert InvalidAmount();
        bytes[] memory calls = new bytes[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            calls[i] = abi.encodeWithSelector(
                this.harvestAndBridge.selector,
                tokens[i],
                compoundPercent[i],
                uint64(0), ///customSlippageBps
                uint256(0) ///minBridgeAmount
            );
        }
        ///execute all harvests atomically
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, ) = address(this).delegatecall(calls[i]);
            if (!success) {
                emit BatchHarvestFailed(tokens[i], i);
            } else {
                emit BatchHarvestSuccess(tokens[i], i);
            }
        }

        emit BatchHarvestCompleted(tokens.length);
    }

    /// @notice Batch collect Slipstream fees from multiple positions
    /// @param tokenIds Array of NFT token IDs to collect fees from
    function batchCollectSlipstreamFees(
        uint256[] calldata tokenIds
    ) external onlyOwner whenNotPaused nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            this.collectSlipstreamFees(tokenIds[i]);
        }
        emit BatchSlipstreamFeesCollected(tokenIds.length);
    }

    /// @notice Batch harvest Slipstream rewards from multiple positions
    /// @param positions Array of position identifiers (token0, token1, fee)
    function batchHarvestSlipstreamRewards(
        SlipstreamPositionIdentifier[] calldata positions
    ) external onlyOwner whenNotPaused nonReentrant {
        for (uint256 i = 0; i < positions.length; i++) {
            this.harvestSlipstreamRewards(
                positions[i].token0,
                positions[i].token1,
                positions[i].fee
            );
        }
        emit BatchSlipstreamRewardsHarvested(positions.length);
    }

    /// @notice Collect fees AND harvest rewards for a Slipstream position in one call
    /// @param tokenId NFT token ID to collect fees from
    /// @param token0 Token0 address (for position hash)
    /// @param token1 Token1 address (for position hash)
    /// @param fee Fee tier
    /// @return fee0 Amount of token0 fees collected
    /// @return fee1 Amount of token1 fees collected
    /// @return rewards Amount of rewards harvested
    function collectFeesAndHarvestRewards(
        uint256 tokenId,
        address token0,
        address token1,
        uint24 fee
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 fee0, uint256 fee1, uint256 rewards)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        // Collect fees
        (fee0, fee1) = ISlipstreamHelper(SLIPSTREAM_HELPER).collectFees(
            tokenId,
            address(this)
        );
        emit SlipstreamFeesCollected(tokenId, fee0, fee1);

        // Harvest rewards
        bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
        rewards = ISlipstreamHelper(SLIPSTREAM_HELPER).harvestRewards(
            positionHash
        );
        emit SlipstreamRewardsHarvested(positionHash, rewards);
    }

    /// @notice Decrease liquidity, collect fees, and optionally unstake in one call
    /// @param params Decrease liquidity parameters
    /// @param token0 Token0 address (for position hash)
    /// @param token1 Token1 address (for position hash)
    /// @param fee Fee tier
    /// @param unstake If true, unstake position after decreasing liquidity
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    /// @return fee0 Amount of token0 fees collected
    /// @return fee1 Amount of token1 fees collected
    function decreaseLiquidityCollectAndUnstake(
        SlipstreamDecreaseParams calldata params,
        address token0,
        address token1,
        uint24 fee,
        bool unstake
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        // Decrease liquidity
        ISlipstreamPositionNFT.DecreaseLiquidityParams
            memory decParams = ISlipstreamPositionNFT.DecreaseLiquidityParams({
                liquidity: params.liquidity,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            });
        (amount0, amount1) = ISlipstreamHelper(SLIPSTREAM_HELPER)
            .decreaseLiquidity(params.tokenId, decParams);
        emit SlipstreamLiquidityDecreased(
            params.tokenId,
            params.liquidity,
            amount0,
            amount1
        );

        // Collect fees
        (fee0, fee1) = ISlipstreamHelper(SLIPSTREAM_HELPER).collectFees(
            params.tokenId,
            address(this)
        );
        emit SlipstreamFeesCollected(params.tokenId, fee0, fee1);

        // Optionally unstake
        if (unstake) {
            bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
            ISlipstreamHelper(SLIPSTREAM_HELPER).unstakePosition(
                params.tokenId,
                positionHash
            );
            emit SlipstreamPositionUnstaked(positionHash, params.tokenId);
        }
    }

    /// @notice Increase liquidity and optionally stake in one call
    /// @param params Increase liquidity parameters
    /// @param token0 Token0 address (for position hash)
    /// @param token1 Token1 address (for position hash)
    /// @param fee Fee tier
    /// @param stake If true, stake position after increasing liquidity
    /// @return liquidity New liquidity amount
    /// @return amount0 Amount of token0 added
    /// @return amount1 Amount of token1 added
    function increaseLiquidityAndStake(
        SlipstreamLiquidityParams calldata params,
        address token0,
        address token1,
        uint24 fee,
        bool stake
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        rateLimitCheck(token0)
        returns (uint256 liquidity, uint256 amount0, uint256 amount1)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        // Transfer tokens to helper
        if (params.amount0Desired > 0) {
            if (_erc20Balance(token0) < params.amount0Desired)
                revert InsufficientBalance();
            token0.safeTransfer(SLIPSTREAM_HELPER, params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            if (_erc20Balance(token1) < params.amount1Desired)
                revert InsufficientBalance();
            token1.safeTransfer(SLIPSTREAM_HELPER, params.amount1Desired);
        }

        // Increase liquidity
        ISlipstreamPositionNFT.IncreaseLiquidityParams
            memory liqParams = ISlipstreamPositionNFT.IncreaseLiquidityParams({
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            });
        (liquidity, amount0, amount1) = ISlipstreamHelper(SLIPSTREAM_HELPER)
            .increaseLiquidity(params.tokenId, liqParams);
        emit SlipstreamLiquidityIncreased(
            params.tokenId,
            liquidity,
            amount0,
            amount1
        );

        // Optionally stake
        if (stake) {
            bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
            ISlipstreamHelper(SLIPSTREAM_HELPER).stakePosition(
                params.tokenId,
                positionHash
            );
            emit SlipstreamPositionStaked(positionHash, params.tokenId);
        }
    }

    /// @notice Full yield cycle: Update yield → Harvest → Zap into Slipstream → Stake
    /// @param token Token to harvest yield from
    /// @param compoundPercent Percentage to compound (0-100)
    /// @param zapAmount Amount to zap into Slipstream (from harvested yield)
    /// @param zapParams Parameters for Slipstream zap
    function fullYieldCycleZapIntoSlipstream(
        address token,
        uint8 compoundPercent,
        uint256 zapAmount,
        ZapSlipstreamParams calldata zapParams
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        rateLimitCheck(token)
        returns (uint256 tokenId)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (tokenMapping[zapParams.tokenOut] == address(0))
            revert TokenNotSupported();

        // Step 1: Update yield
        _updateYield(token);

        // Step 2: Harvest yield
        _harvestAndBridgeInternal(token, compoundPercent, 0, 0);

        // Step 3: Zap into Slipstream position
        if (_erc20Balance(token) < zapAmount) revert InsufficientBalance();
        token.safeTransfer(SLIPSTREAM_HELPER, zapAmount);
        tokenId = ISlipstreamHelper(SLIPSTREAM_HELPER).zapIntoPosition(
            token,
            zapParams.tokenOut,
            zapAmount,
            zapParams.fee,
            zapParams.tickLower,
            zapParams.tickUpper,
            zapParams.minAmount0,
            zapParams.minAmount1,
            zapParams.stakeInGauge
        );

        emit SlipstreamPositionCreated(
            tokenId,
            token,
            zapParams.tokenOut,
            zapParams.fee,
            zapParams.stakeInGauge
        );
        emit FullYieldCycleCompleted(token, tokenId, zapAmount);
    }

    /// @notice Auto-deposit available bridged funds (keeper friendly)
    /// @param token L2 token address
    /// @param useSmartAllocation If true, use YieldAllocator for optimal strategy allocation
    /// @dev Detects new token balance from bridge and automatically deposits
    /// @dev If YieldAllocator is set and useSmartAllocation=true, allocates to best strategy
    /// @dev Otherwise, deposits to Tydro
    function depositAvailable(
        address token,
        bool useSmartAllocation
    ) external whenNotPaused nonReentrant rateLimitCheck(token) {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (token == address(0)) revert InvalidAddress();

        TokenStatus storage status = tokenStatus[token];
        uint256 currentBalance = _erc20Balance(token);
        uint256 depositedAmount = status.depositedAmount;
        ///new balance to deposit ?
        if (currentBalance <= depositedAmount) {
            emit AutoDepositSkipped(
                token,
                currentBalance,
                depositedAmount,
                msg.sender
            );
            return;
        }
        uint256 newAmount = currentBalance - depositedAmount;
        if (newAmount == 0) revert InvalidAmount();
        if (maxDeposits[token] > 0) {
            uint256 newTotal = status.depositedAmount + newAmount;
            if (newTotal > maxDeposits[token]) revert DepositLimitExceeded();
        }

        ///Use smart allocation if enabled && allocator is set
        if (useSmartAllocation && address(yieldAllocator) != address(0)) {
            SafeTransferLib.safeApprove(
                token,
                address(yieldAllocator),
                newAmount
            );
            yieldAllocator.allocateFunds(token, newAmount, 0); ///0 = autoselect best strategy
            emit AutoDeposited(token, newAmount, msg.sender, true);
        } else {
            ///Default deposit to Tydro
            _depositToTydro(token, newAmount);
            emit AutoDeposited(token, newAmount, msg.sender, false);
        }
    }

    /// @notice Auto-deposit available bridged funds to Tydro (no smart allocation)
    /// @param token L2 token address
    /// @dev No smart allocation
    function depositAvailable(
        address token
    ) external whenNotPaused nonReentrant rateLimitCheck(token) {
        if (emergencyMode) revert EmsModeInit();
        this.depositAvailable(token, false);
    }

    /// @notice Deposit treasury tokens to Tydro pool
    /// @param token L2 token address
    /// @param amount Amount to deposit
    function deposit(
        address token,
        uint256 amount
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        rateLimitCheck(token)
        withdrawalLimitCheck(token, amount)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (maxDeposits[token] > 0) {
            TokenStatus storage status = tokenStatus[token];
            if (status.depositedAmount + amount > maxDeposits[token])
                revert DepositLimitExceeded();
        }
        SafeTransferLib.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );
        _depositToTydro(token, amount);

        emit Deposited(token, amount, msg.sender);
    }

    /// @notice Internal function to deposit tokens to Tydro pool
    /// @param token L2 token address
    /// @param amount Amount to deposit
    function _depositToTydro(address token, uint256 amount) internal {
        uint256 balanceBefore = _erc20Balance(token);
        if (balanceBefore < amount) revert InsufficientBalance();
        uint256 currentAllowance = _erc20Allowance(token, TYDRO_POOL);
        if (currentAllowance < amount) {
            SafeTransferLib.safeApprove(token, TYDRO_POOL, 0);
            SafeTransferLib.safeApprove(token, TYDRO_POOL, amount);
        }

        bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(
            token,
            amount,
            0
        );
        try IL2Pool(TYDRO_POOL).supply(supplyArgs) {
            emit HarvestStep(token, "depo_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "deposit_failed");
            if (reason.length >= 4) {
                bytes4 selector = bytes4(reason);
                if (selector == bytes4(0xa4937508)) {
                    revert DepositFailed(); ///NotEnoughAvailableLiquidity
                }
            }
            revert DepositFailed();
        }
        if (_aTokens[token] == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(
                TYDRO_POOL
            ).getReserveData(token);
            _aTokens[token] = aTokenAddress;
        }
        TokenStatus storage status = tokenStatus[token];
        unchecked {
            status.depositedAmount += uint128(amount);
            status.currentBalance += uint128(amount);
            status.lastUpdate = uint32(block.timestamp);
        }
    }

    /// @notice Get current status for a token
    function getStatus(
        address token
    )
        external
        view
        returns (
            uint256 depositedAmount,
            uint256 currentBalance,
            uint256 yieldAvailable,
            uint256 gasBalance
        )
    {
        TokenStatus storage status = tokenStatus[token];
        return (
            status.depositedAmount,
            status.currentBalance,
            status.yieldAvailable,
            address(this).balance
        );
    }

    /// @notice Check available yield for a token using aToken balance from Tydro (Aave-style)
    function getYieldAvailable(
        address token
    ) external view returns (uint256 yield) {
        TokenStatus storage status = tokenStatus[token];
        address aToken = _aTokens[token];
        if (aToken == address(0)) {
            ///Query Tydro Pool for reserve data to get aToken address
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(
                TYDRO_POOL
            ).getReserveData(token);
            aToken = aTokenAddress;
        }
        uint256 currentBalance = aToken == address(0)
            ? 0
            : IAToken(aToken).balanceOf(address(this));
        uint256 deposited = status.depositedAmount;
        if (currentBalance > deposited) {
            return currentBalance - deposited;
        }
        return 0;
    }

    /// @notice Update yield available
    function updateYield(address token) external {
        _updateYield(token);
    }

    /// @notice Internal function to update yield (avoids external call overhead)
    function _updateYield(address token) internal {
        TokenStatus storage status = tokenStatus[token];
        address aToken = _aTokens[token];
        if (aToken == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(
                TYDRO_POOL
            ).getReserveData(token);
            _aTokens[token] = aTokenAddress;
            aToken = aTokenAddress;
        }
        uint256 currentBalance = aToken == address(0)
            ? 0
            : IAToken(aToken).balanceOf(address(this));
        uint256 deposited = status.depositedAmount;
        status.currentBalance = uint128(currentBalance);
        status.lastUpdate = uint32(block.timestamp);
        if (currentBalance > deposited) {
            uint256 y = currentBalance - deposited;
            status.yieldAvailable = uint128(y);
            emit YieldUpdated(token, y);
        } else {
            status.yieldAvailable = 0;
            emit YieldUpdated(token, 0);
        }
    }

    /// @notice Internal harvest and bridge logic (shared by owner and auto-harvest)
    function _harvestAndBridgeInternal(
        address token,
        uint8 compoundPercent,
        uint64 customSlippageBps,
        uint256 minBridgeAmount
    ) internal {
        if (emergencyMode) revert EmsModeInit();
        if (breakerActive) revert CircuitBreakerActive();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (l1Recipient == address(0)) revert L1RecipientNotSet();
        if (compoundPercent > 100) revert InvalidCompoundPercent();
        if (customSlippageBps > 1000) revert InvalidSlippage();
        bool needsGasRefill = address(this).balance < minGasBalance;
        if (needsGasRefill && autoGasRefillBps == 0) revert InsufficientGas();
        ///Update yield
        _updateYield(token);
        emit HarvestStep(token, "yield_updated");

        TokenStatus storage status = tokenStatus[token];
        uint256 principal = status.depositedAmount;
        if (principal == 0) revert InsufficientYield();
        ///Wd from Tydro
        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(
            token,
            type(uint256).max
        );
        uint256 withdrawn;
        try IL2Pool(TYDRO_POOL).withdraw(withdrawArgs) returns (
            uint256 amountWithdrawn
        ) {
            withdrawn = amountWithdrawn;
            emit HarvestStep(token, "_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "_failed");
            ///Log revert
            if (reason.length >= 4) {
                bytes4 selector = bytes4(reason);
                if (selector == bytes4(0xa4937508)) {
                    revert WithdrawFailed(); ///NotEnoughAvailableLiquidity
                }
            }
            revert WithdrawFailed();
        }
        if (withdrawn <= principal) revert InsufficientYield();

        uint256 yieldAmount = withdrawn - principal;
        status.yieldAvailable = 0;
        ///Calculate split
        uint256 compoundAmount;
        uint256 bridgeAmount;
        assembly {
            compoundAmount := mul(yieldAmount, compoundPercent)
            compoundAmount := div(compoundAmount, 100)
            bridgeAmount := sub(yieldAmount, compoundAmount)
        }
        ///Resupply principal + compound amount
        uint256 resupplyAmount = principal + compoundAmount;
        uint256 balanceBeforeResupply = _erc20Balance(token);
        if (balanceBeforeResupply < resupplyAmount)
            revert InsufficientBalance();

        SafeTransferLib.safeApprove(token, TYDRO_POOL, 0);
        SafeTransferLib.safeApprove(token, TYDRO_POOL, resupplyAmount);

        bytes32 resupplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(
            token,
            resupplyAmount,
            0
        );
        try IL2Pool(TYDRO_POOL).supply(resupplyArgs) {
            status.depositedAmount = uint128(resupplyAmount);
            status.currentBalance = uint128(resupplyAmount);
            status.lastUpdate = uint32(block.timestamp);
            emit HarvestStep(token, "_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "_failed");
            revert DepositFailed();
        }
        if (compoundAmount > 0) {
            emit YieldCompounded(token, compoundAmount);
        }

        emit YieldHarvested(token, yieldAmount);
        if (bridgeAmount > 0) {
            address l1Token = tokenMapping[token];
            uint64 slippageBps = customSlippageBps > 0
                ? customSlippageBps
                : defaultSlippageBps;
            if (slippageBps > 1000) revert InvalidSlippage(); ///Max 10%
            uint256 minAmountOut;
            if (minBridgeAmount > 0) {
                uint256 expectedAmount = (bridgeAmount *
                    (10000 - slippageBps)) / 10000;
                if (minBridgeAmount > expectedAmount) revert SlippageTooHigh();
                minAmountOut = minBridgeAmount;
            } else {
                minAmountOut = (bridgeAmount * (10000 - slippageBps)) / 10000;
            }
            ///refill if needed
            uint256 actualBridgeAmount = bridgeAmount;
            if (needsGasRefill && autoGasRefillBps > 0) {
                uint256 gasRefillAmount = (bridgeAmount * autoGasRefillBps) /
                    10000;
                if (gasRefillAmount > 0.0069 ether) {
                    gasRefillAmount = 0.0069 ether;
                }
                if (gasRefillAmount <= bridgeAmount) {
                    actualBridgeAmount -= gasRefillAmount;
                    emit GasRefilled(address(this), gasRefillAmount);
                }
            }

            if (actualBridgeAmount > 0) {
                ///Recalculate minAmountOut for reduced amount
                if (minBridgeAmount == 0) {
                    minAmountOut =
                        (actualBridgeAmount * (10000 - slippageBps)) /
                        10000;
                } else {
                    minAmountOut =
                        (minAmountOut * actualBridgeAmount) /
                        bridgeAmount;
                }
                uint256 balanceBeforeBridge = _erc20Balance(token);
                if (balanceBeforeBridge < actualBridgeAmount)
                    revert InsufficientBalance();

                uint256 currentAllowance = _erc20Allowance(
                    token,
                    ACROSS_SPOKE_POOL
                );
                if (currentAllowance < actualBridgeAmount) {
                    SafeTransferLib.safeApprove(token, ACROSS_SPOKE_POOL, 0);
                    SafeTransferLib.safeApprove(
                        token,
                        ACROSS_SPOKE_POOL,
                        actualBridgeAmount
                    );
                }
                emit HarvestStep(token, "bridge_attempting");
                ///Try depositV3 first... fallback to legacy deposit if needed
                /// https://docs.across.to/reference/selected-contract-functions save 4 l8r
                bytes memory message = abi.encode(l1Recipient);
                bool bridgeSuccess = false;
                ///Try depositV3 first
                try
                    this._tryDepositV3(
                        token,
                        l1Token,
                        actualBridgeAmount,
                        minAmountOut,
                        message
                    )
                {
                    bridgeSuccess = true;
                    emit HarvestStep(token, "bridge_success_v3");
                } catch (bytes memory reason) {
                    emit HarvestStep(token, "bridge_v3_failed");
                    ///Log err but continue legacy deposit
                    if (reason.length >= 4) {
                        bytes4 selector = bytes4(reason);
                        emit BridgeError(
                            token,
                            selector,
                            actualBridgeAmount,
                            minAmountOut
                        );
                    }
                }
                ///Fallback to legacy depo
                if (!bridgeSuccess) {
                    try
                        this._tryDepositLegacy(
                            token,
                            l1Token,
                            actualBridgeAmount,
                            minAmountOut,
                            message
                        )
                    {
                        bridgeSuccess = true;
                        emit HarvestStep(token, "bridge_success_legacy");
                    } catch (bytes memory reason) {
                        emit HarvestStep(token, "bridge_legacy_failed");
                        if (reason.length >= 4) {
                            bytes4 selector = bytes4(reason);
                            emit BridgeError(
                                token,
                                selector,
                                actualBridgeAmount,
                                minAmountOut
                            );
                        }
                    }
                }
                if (bridgeSuccess) {
                    emit YieldBridged(token, actualBridgeAmount);
                    emit HarvestStep(token, "bridge_success");
                } else {
                    revert BridgeFailed();
                }
            }
        }
    }

    /// @notice Harvest yield and bridge to L1 treasury (Owner only)
    /// @param token L2 token address
    /// @param compoundPercent Percentage to compound (0-100), rest goes to L1
    /// @param customSlippageBps Optional custom slippage (0 = use default)
    /// @param minBridgeAmount Minimum amount to receive on L1 (0 = calculated from slippage)
    function harvestAndBridge(
        address token,
        uint8 compoundPercent,
        uint64 customSlippageBps,
        uint256 minBridgeAmount
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        _harvestAndBridgeInternal(
            token,
            compoundPercent,
            customSlippageBps,
            minBridgeAmount
        );
    }

    /// @notice Permissionless auto-harvest and bridge (keeper-friendly)
    /// @param token L2 token address
    /// @dev Uses default compound percent and slippage settings
    /// @dev Only harvests if yield exceeds minimum threshold
    function autoHarvestAndBridge(
        address token
    ) external whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        if (breakerActive) revert CircuitBreakerActive();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (l1Recipient == address(0)) revert L1RecipientNotSet();
        if (maxOperationsPerHour > 0) {
            uint32 currentHour = uint32(block.timestamp / 3600);
            if (operationsThisHour[currentHour] >= maxOperationsPerHour) {
                revert RateLimitExceeded();
            }
        }
        if (operationCooldown[token] > 0) {
            if (
                block.timestamp <
                lastOperationTime[token] + operationCooldown[token]
            ) {
                revert OperationCooldown();
            }
        }

        ///Update yield to get current yieldAvailable
        _updateYield(token);

        TokenStatus storage status = tokenStatus[token];
        uint256 yieldAvailable = status.yieldAvailable;
        uint256 principal = status.depositedAmount;

        if (principal == 0) revert InsufficientYield();

        ///Check minimum yield threshold (e.g., 0.1% of principal)
        uint256 minYieldThreshold = (principal * minYieldThresholdBps) / 10000;
        if (yieldAvailable < minYieldThreshold) revert InsufficientYield();

        ///Increment rate limits AFTER checks pass (before expensive operations)
        if (maxOperationsPerHour > 0) {
            uint32 currentHour = uint32(block.timestamp / 3600);
            operationsThisHour[currentHour]++;
        }
        if (operationCooldown[token] > 0) {
            lastOperationTime[token] = uint32(block.timestamp);
        }

        ///Call internal harvest logic with default settings
        ///Note: _harvestAndBridgeInternal will call _updateYield again, but that's fine
        ///as it ensures we have the latest yield before harvesting
        _harvestAndBridgeInternal(token, defaultCompoundPercent, 0, 0);
    }

    /// @notice Batch auto-harvest multiple tokens (keeper-friendly)
    /// @param tokens Array of L2 token addresses
    /// @dev Silently skips tokens that fail (rate limited, insufficient yield, etc.)
    function autoHarvestAll(address[] calldata tokens) external whenNotPaused {
        for (uint256 i = 0; i < tokens.length; i++) {
            try this.autoHarvestAndBridge(tokens[i]) {
                emit AutoHarvested(tokens[i], true);
            } catch {
                emit AutoHarvested(tokens[i], false);
            }
        }
    }

    /// @notice Set default compound percent for auto-harvest
    function setDefaultCompoundPercent(uint8 _percent) external onlyOwner {
        if (_percent > 100) revert InvalidCompoundPercent();
        uint8 oldPercent = defaultCompoundPercent;
        defaultCompoundPercent = _percent;
        emit DefaultCompoundPercentUpdated(oldPercent, _percent);
    }

    /// @notice Set minimum yield threshold for auto-harvest (basis points)
    function setMinYieldThreshold(uint64 _thresholdBps) external onlyOwner {
        if (_thresholdBps > 1000) revert(); ///Max 10%
        uint64 oldThreshold = minYieldThresholdBps;
        minYieldThresholdBps = _thresholdBps;
        emit MinYieldThresholdUpdated(oldThreshold, _thresholdBps);
    }

    /// @notice Auto-deposit and harvest in one call
    /// @param token L2 token address
    /// @param compoundPercent Percentage to compound (0-100), rest goes to L1
    /// @param customSlippageBps Optional custom slippage (0 = use default)
    /// @param minBridgeAmount Minimum amount to receive on L1 (0 = calculated from slippage)
    /// @dev First auto-deposits any available bridged funds, then harvests yield
    function depositAndHarvest(
        address token,
        uint8 compoundPercent,
        uint64 customSlippageBps,
        uint256 minBridgeAmount
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        ///auto-deposit any available bridged funds (call via this to access external function)
        this.depositAvailable(token);
        this.harvestAndBridge(
            token,
            compoundPercent,
            customSlippageBps,
            minBridgeAmount
        );
    }

    /// @notice Smart rebalance: automatically rebalance funds to highest-yielding strategy
    /// @param token Token to rebalance
    /// @dev Requires YieldAllocator to be set
    function smartRebalance(
        address token
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        if (emergencyMode) revert EmsModeInit();
        if (address(yieldAllocator) == address(0)) revert AllocatorNotSet();
        yieldAllocator.autoRebalance(token);
        emit SmartRebalanced(token, 0);
    }

    function smartCompound(
        address token
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        if (emergencyMode) revert EmsModeInit();
        if (address(yieldAllocator) == address(0)) revert AllocatorNotSet();
        yieldAllocator.smartCompound(token);
        emit SmartCompounded(token, 0);
    }

    /// @notice Get best strategy for a token (if allocator is set)
    function getBestStrategy(
        address token
    ) external view returns (uint8 strategyId, uint256 apyBps) {
        if (address(yieldAllocator) == address(0)) {
            ///Default: Tydro (strategy ID 1)//usdt0
            return (1, 0);
        }
        return yieldAllocator.getBestStrategy(token);
    }

    /// @notice Internal helper to get ERC20 balance
    function _erc20Balance(address token) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    /// @notice Internal helper to get ERC20 allowance
    function _erc20Allowance(
        address token,
        address spender
    ) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature(
                "allowance(address,address)",
                address(this),
                spender
            )
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    /// @notice Try depositV3 (external function for try-catch)
    function _tryDepositV3(
        address token,
        address l1Token,
        uint256 actualBridgeAmount,
        uint256 minAmountOut,
        bytes memory message
    ) external {
        require(msg.sender == address(this), "Internal only");
        ///Get quote timestamp buffer and calculate valid quoteTimestamp
        uint32 quoteTimeBuffer = ISpokePool(ACROSS_SPOKE_POOL)
            .depositQuoteTimeBuffer();
        uint256 currentTime = ISpokePool(ACROSS_SPOKE_POOL).getCurrentTime();
        uint32 quoteTimestamp = uint32(currentTime);
        ///Validate quoteTimestamp is within buffer
        if (
            quoteTimestamp > uint32(currentTime + quoteTimeBuffer) ||
            quoteTimestamp < uint32(currentTime - quoteTimeBuffer)
        ) {
            revert BridgeFailed();
        }
        uint32 fillDeadlineBuffer = ISpokePool(ACROSS_SPOKE_POOL)
            .fillDeadlineBuffer();
        uint32 fillDeadline = uint32(block.timestamp + fillDeadlineBuffer);

        ISpokePool(ACROSS_SPOKE_POOL).depositV3(
            address(this), ///depositor
            l1Recipient, ///recipient
            token, ///inputToken (L2)
            l1Token, ///outputToken (L1)
            actualBridgeAmount, ///inputAmount
            minAmountOut, ///outputAmount (minimum)
            L1_CHAIN_ID, ///destinationChainId
            address(0), ///exclusiveRelayer (none)
            quoteTimestamp, ///quoteTimestamp
            fillDeadline, ///fillDeadline
            0, ///exclusivityDeadline
            message ///message
        );
    }

    /// @notice Try legacy deposit
    function _tryDepositLegacy(
        address token,
        address l1Token,
        uint256 actualBridgeAmount,
        uint256 minAmountOut,
        bytes memory message
    ) external {
        require(msg.sender == address(this), "Internal only");
        ///Legacy deposit = block.timestamp for quoteTimestamp
        uint32 quoteTimestamp = uint32(block.timestamp);
        ISpokePool(ACROSS_SPOKE_POOL).deposit(
            address(this), ///depositor
            l1Recipient, ///recipient
            token, ///inputToken (L2)
            l1Token, ///outputToken (L1)
            actualBridgeAmount, ///inputAmount
            minAmountOut, ///outputAmount (minimum)
            L1_CHAIN_ID, ///destinationChainId
            0, ///relayerFeePct
            quoteTimestamp, ///quoteTimestamp
            message, ///message
            0 ///maxCount (0 = no limit)
        );
    }

    /// @notice Set the L1 token address for a given L2 token
    function mapToken(address l2Token, address l1Token) external onlyOwner {
        if (l2Token == address(0) || l1Token == address(0))
            revert InvalidAddress();
        tokenMapping[l2Token] = l1Token;
        emit TokenMappingSet(l2Token, l1Token);
    }

    /// @notice Set the YieldAllocator for smart multi-strategy allocation
    function setAllocator(YieldAllocator _yieldAllocator) external onlyOwner {
        yieldAllocator = _yieldAllocator;
        emit YieldAllocatorSet(address(_yieldAllocator));
    }

    /// @notice Set the L1 recipient address
    function setL1Recipient(address _l1Recipient) external onlyOwner {
        if (_l1Recipient == address(0)) revert InvalidAddress();
        address oldRecipient = l1Recipient;
        l1Recipient = _l1Recipient;
        emit L1RecipientSet(oldRecipient, _l1Recipient);
    }

    /// @notice Set minimum gas balance required
    function setMinGasBal(uint128 _minGasBalance) external onlyOwner {
        uint128 oldMin = minGasBalance;
        minGasBalance = _minGasBalance;
        emit MinGasBalanceUpdated(oldMin, _minGasBalance);
    }

    /// @notice Set default slippage for bridging
    function setDefaultSlippage(uint64 _slippageBps) external onlyOwner {
        if (_slippageBps > 1000) revert InvalidSlippage(); ///Max 10%
        uint64 oldSlippage = defaultSlippageBps;
        defaultSlippageBps = _slippageBps;
        emit SlippageUpdated(oldSlippage, _slippageBps);
    }

    function setAutoRefill(uint64 _autoGasRefillBps) external onlyOwner {
        if (_autoGasRefillBps > 500) revert InvalidSlippage();
        uint64 oldBps = autoGasRefillBps;
        autoGasRefillBps = _autoGasRefillBps;
        emit AutoGasRefillUpdated(oldBps, _autoGasRefillBps);
    }

    function setMaxDeposit(
        address token,
        uint128 maxAmount
    ) external onlyOwner {
        uint128 oldMax = maxDeposits[token];
        maxDeposits[token] = maxAmount;
        emit MaxDepositUpdated(token, oldMax, maxAmount);
    }

    function getVaultHealth(
        address token
    )
        external
        view
        returns (
            bool isHealthy,
            bool hasGas,
            bool hasYield,
            uint256 timeSinceLastUpdate,
            uint256 totalValueLocked
        )
    {
        TokenStatus storage status = tokenStatus[token];
        bool healthy = !emergencyMode && !breakerActive && !paused();
        bool gasOk = address(this).balance >= minGasBalance;
        /// get aToken and check yield [[only if registered]
        address aToken = _aTokens[token];
        uint256 currentBalance = 0;
        bool yieldExists = false;

        if (aToken == address(0)) {
            try IL2Pool(TYDRO_POOL).getReserveData(token) returns (
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
                aToken = aTokenAddress;
            } catch {
                ///not registered -- return vault state but no yield info
                uint256 timeSinceUpdate = block.timestamp > status.lastUpdate
                    ? block.timestamp - status.lastUpdate
                    : 0;
                return (healthy, gasOk, false, timeSinceUpdate, 0);
            }
        }
        ///registered -- check yield
        if (aToken != address(0)) {
            currentBalance = IAToken(aToken).balanceOf(address(this));
            yieldExists = currentBalance > status.depositedAmount;
        }

        uint256 timeSinceUpdate = block.timestamp > status.lastUpdate
            ? block.timestamp - status.lastUpdate
            : 0;
        return (healthy, gasOk, yieldExists, timeSinceUpdate, currentBalance);
    }

    function getTotalValueLocked(
        address[] calldata tokens
    ) external view returns (uint256 total) {
        for (uint256 i = 0; i < tokens.length; i++) {
            address aToken = _aTokens[tokens[i]];
            if (aToken == address(0)) {
                try IL2Pool(TYDRO_POOL).getReserveData(tokens[i]) returns (
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
                    aToken = aTokenAddress;
                } catch {
                    continue;
                }
            }
            if (aToken != address(0)) {
                total += IAToken(aToken).balanceOf(address(this));
            }
        }
    }

    function canPerformOp(
        address token
    ) external view returns (bool canOperate, string memory reason) {
        if (emergencyMode) return (false, "Emergency mode active");
        if (breakerActive) return (false, "Circuit breaker active");
        if (paused()) return (false, "Contract paused");
        if (tokenMapping[token] == address(0))
            return (false, "Token not supported");
        if (address(this).balance < minGasBalance)
            return (false, "Insufficient gas");
        if (maxOperationsPerHour > 0) {
            uint32 currentHour = uint32(block.timestamp / 3600);
            if (operationsThisHour[currentHour] >= maxOperationsPerHour) {
                return (false, "Rate limit exceeded");
            }
        }

        if (operationCooldown[token] > 0) {
            if (
                block.timestamp <
                lastOperationTime[token] + operationCooldown[token]
            ) {
                return (false, "Operation cooldown active");
            }
        }

        return (true, "");
    }

    function estimateBridgeFee(
        address token,
        uint256 amount
    ) external view returns (uint256 estimatedFee) {
        if (tokenMapping[token] == address(0)) return 0;
        uint64 slippageBps = defaultSlippageBps;
        uint256 minAmountOut = (amount * (10000 - slippageBps)) / 10000;
        if (autoGasRefillBps > 0 && address(this).balance < minGasBalance) {
            uint256 gasRefillAmount = (amount * autoGasRefillBps) / 10000;
            if (gasRefillAmount > 0.01 ether) {
                gasRefillAmount = 0.01 ether;
            }
            estimatedFee = gasRefillAmount;
        }

        return estimatedFee;
    }

    function getATokenAddress(address token) external view returns (address) {
        address aToken = _aTokens[token];
        if (aToken != address(0)) return aToken;
        try IL2Pool(TYDRO_POOL).getReserveData(token) returns (
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
            return aTokenAddress;
        } catch {
            return address(0);
        }
    }

    /// @notice mo mo auto-compound: compounds yield more frequently for higher APY
    /// @param token Token to compound
    /// @param minYieldThreshold Minimum yield amount to trigger compound (0 = always compound)
    /// @dev More frequent compounding increases effective APY
    function momoCompound(
        address token,
        uint256 minYieldThreshold
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(token) {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        _updateYield(token);
        TokenStatus storage status = tokenStatus[token];

        uint256 currentYield = status.yieldAvailable;
        if (currentYield < minYieldThreshold) return;
        uint256 principal = status.depositedAmount;
        if (principal == 0) revert InsufficientYield();
        ///Withdraw all & get yield
        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(
            token,
            type(uint256).max
        );
        uint256 withdrawn = IL2Pool(TYDRO_POOL).withdraw(withdrawArgs);
        if (withdrawn <= principal) revert InsufficientYield();

        uint256 yieldAmount = withdrawn - principal;
        ///Compound 100% back (no bridge)
        uint256 resupplyAmount = principal + yieldAmount;
        SafeTransferLib.safeApprove(token, TYDRO_POOL, 0);
        SafeTransferLib.safeApprove(token, TYDRO_POOL, resupplyAmount);
        bytes32 resupplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(
            token,
            resupplyAmount,
            0
        );
        IL2Pool(TYDRO_POOL).supply(resupplyArgs);

        status.depositedAmount = uint128(resupplyAmount);
        status.currentBalance = uint128(resupplyAmount);
        status.yieldAvailable = 0;
        status.lastUpdate = uint32(block.timestamp);

        emit YieldCompounded(token, yieldAmount);
        emit YieldHarvested(token, yieldAmount);
    }

    /// @notice Get current APY for a token from Tydro
    /// @return apyBps APY in basis points (e.g., 500 = 5%)
    function getCurrentAPY(
        address token
    ) external view returns (uint256 apyBps) {
        try IL2Pool(TYDRO_POOL).getReserveData(token) returns (
            uint256,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            ///Convert rate to APY: rate * 365 days / 1e18 * 10000 (for bps)
            ///currentLiquidityRate is in ray (1e27),
            uint256 annualRate = (uint256(currentLiquidityRate) * 365 days) /
                1e9; ///Convert ray to annual
            apyBps = (annualRate * 10000) / 1e18;
        } catch {
            return 0;
        }
    }

    /// @notice Optimize yield by comparing rates across multiple tokens
    /// @param tokens Array of tokens to compare
    /// @return bestToken Token with highest APY
    /// @return bestAPY Highest APY in basis points
    function findBestYieldToken(
        address[] calldata tokens
    ) external view returns (address bestToken, uint256 bestAPY) {
        bestAPY = 0;
        bestToken = address(0);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 apy = this.getCurrentAPY(tokens[i]);
            if (apy > bestAPY) {
                bestAPY = apy;
                bestToken = tokens[i];
            }
        }
    }

    /// @notice Create Velodrome LP
    /// @param sendToOwner If true, LP tokens go to owner's EOA (visible in Velodrome UI). If false, stay in vault (automated).
    function createVelodromeLP(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable,
        bool stakeInGauge,
        bool sendToOwner
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(tokenA) {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[tokenA] == address(0)) revert TokenNotSupported();
        if (_erc20Balance(tokenA) < amountA) revert InsufficientBalance();
        if (_erc20Balance(tokenB) < amountB) revert InsufficientBalance();
        tokenA.safeTransfer(VELO_HELPER, amountA);
        tokenB.safeTransfer(VELO_HELPER, amountB);
        bool shouldStake = stakeInGauge && !sendToOwner;
        uint256 liquidity = IVelodromeHelper(VELO_HELPER).createLP(
            tokenA,
            tokenB,
            amountA,
            amountB,
            stable,
            shouldStake
        );
        ///Optional: Send LP to owner's EOA 4 ui
        if (sendToOwner) {
            address pair = IVeloRouter(VELO_ROUTER).pairFor(
                tokenA,
                tokenB,
                stable
            );
            if (pair != address(0)) {
                IVelodromeHelper(VELO_HELPER).transferLP(
                    pair,
                    owner(),
                    liquidity
                );
                emit VelodromeLPSentToOwner(pair, liquidity, owner());
            }
        }
    }

    /// @notice Zap into LP
    /// @param sendToOwner If true, LP tokens go to owner's EOA (visible in Velodrome UI). If false, stay in vault (automated).
    function zapIntoLP(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool stable,
        bool stakeInGauge,
        uint256 minLiquidity,
        bool sendToOwner
    ) external onlyOwner whenNotPaused nonReentrant rateLimitCheck(tokenIn) {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[tokenIn] == address(0)) revert TokenNotSupported();
        if (tokenMapping[tokenOut] == address(0)) revert TokenNotSupported();
        if (_erc20Balance(tokenIn) < amountIn) revert InsufficientBalance();
        tokenIn.safeTransfer(VELO_HELPER, amountIn);
        ///If sending to owner, don't stake in gauge (owner can stake manuallyif they want)
        bool shouldStake = stakeInGauge && !sendToOwner;
        uint256 liquidity = IVelodromeHelper(VELO_HELPER).zapIntoLP(
            tokenIn,
            tokenOut,
            amountIn,
            stable,
            shouldStake,
            minLiquidity
        );
        ///Optional: Send LP to owner's EOA 4 ui
        if (sendToOwner) {
            address pair = IVeloRouter(VELO_ROUTER).pairFor(
                tokenIn,
                tokenOut,
                stable
            );
            if (pair != address(0)) {
                IVelodromeHelper(VELO_HELPER).transferLP(
                    pair,
                    owner(),
                    liquidity
                );
                emit VelodromeLPSentToOwner(pair, liquidity, owner());
            }
        }
    }

    /// @notice Configure LeafCLGauge for Slipstream positions
    function setSlipstreamGauge(
        address tokenA,
        address tokenB,
        uint24 fee,
        address gauge
    ) external onlyOwner {
        ISlipstreamHelper(SLIPSTREAM_HELPER).setLeafGauge(
            tokenA,
            tokenB,
            fee,
            gauge
        );
        emit SlipstreamGaugeSet(tokenA, tokenB, fee, gauge);
    }

    /// @notice Zap single token into Slipstream position (via SlipstreamHelper)
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address (for the pair)
    /// @param amountIn Amount of tokenIn to zap
    /// @param fee Fee tier (e.g., 100 = 0.01%)
    /// @param tickLower Lower tick for the position
    /// @param tickUpper Upper tick for the position
    /// @param minAmount0 Minimum amount of token0 (for slippage protection)
    /// @param minAmount1 Minimum amount of token1 (for slippage protection)
    /// @param stakeInGauge If true, stake NFT in LeafCLGauge after minting
    /// @return tokenId The NFT token ID of the created position
    function zapIntoSlipstreamPosition(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 minAmount0,
        uint256 minAmount1,
        bool stakeInGauge
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        rateLimitCheck(tokenIn)
        returns (uint256 tokenId)
    {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[tokenIn] == address(0)) revert TokenNotSupported();
        if (tokenMapping[tokenOut] == address(0)) revert TokenNotSupported();
        if (_erc20Balance(tokenIn) < amountIn) revert InsufficientBalance();
        tokenIn.safeTransfer(SLIPSTREAM_HELPER, amountIn);
        ///Zap via helper (swaps half, creates position)
        tokenId = ISlipstreamHelper(SLIPSTREAM_HELPER).zapIntoPosition(
            tokenIn,
            tokenOut,
            amountIn,
            fee,
            tickLower,
            tickUpper,
            minAmount0,
            minAmount1,
            stakeInGauge
        );

        emit SlipstreamPositionCreated(
            tokenId,
            tokenIn,
            tokenOut,
            fee,
            stakeInGauge
        );
    }

    /// @notice Create Slipstream concentrated liquidity position (NFT)
    /// @param params Mint parameters (amounts pulled from vault)
    /// @param stakeInGauge If true, stake NFT in LeafCLGauge immediately
    function createSlipstreamPosition(
        SlipstreamMintParams calldata params,
        bool stakeInGauge
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        rateLimitCheck(params.token0)
    {
        if (emergencyMode) revert EmsModeInit();
        if (params.token0 == address(0) || params.token1 == address(0))
            revert InvalidAddress();
        if (tokenMapping[params.token0] == address(0))
            revert TokenNotSupported();
        if (tokenMapping[params.token1] == address(0))
            revert TokenNotSupported();
        if (params.amount0Desired == 0 && params.amount1Desired == 0)
            revert InvalidAmount();

        if (params.amount0Desired > 0) {
            if (_erc20Balance(params.token0) < params.amount0Desired)
                revert InsufficientBalance();
            params.token0.safeTransfer(
                SLIPSTREAM_HELPER,
                params.amount0Desired
            );
        }
        if (params.amount1Desired > 0) {
            if (_erc20Balance(params.token1) < params.amount1Desired)
                revert InsufficientBalance();
            params.token1.safeTransfer(
                SLIPSTREAM_HELPER,
                params.amount1Desired
            );
        }

        ISlipstreamPositionNFT.MintParams
            memory mintParams = ISlipstreamPositionNFT.MintParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: SLIPSTREAM_HELPER,
                deadline: params.deadline
            });

        uint256 tokenId = ISlipstreamHelper(SLIPSTREAM_HELPER).createPosition(
            mintParams,
            stakeInGauge
        );
        emit SlipstreamPositionCreated(
            tokenId,
            params.token0,
            params.token1,
            params.fee,
            stakeInGauge
        );
    }

    /// @notice Increase liquidity of existing Slipstream position
    function increaseSlipstreamLiquidity(
        SlipstreamLiquidityParams calldata params
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        (address token0, address token1, , , , ) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).getPosition(params.tokenId);
        if (token0 == address(0) || token1 == address(0))
            revert InvalidAddress();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();
        /// Rate limit check (manual since we need to determine token first) - delete this prob
        address rateLimitToken = params.amount0Desired > 0 ? token0 : token1;
        if (maxOperationsPerHour > 0) {
            uint32 currentHour = uint32(block.timestamp / 3600);
            if (operationsThisHour[currentHour] >= maxOperationsPerHour) {
                revert RateLimitExceeded();
            }
            operationsThisHour[currentHour]++;
        }
        if (operationCooldown[rateLimitToken] > 0) {
            if (
                block.timestamp <
                lastOperationTime[rateLimitToken] +
                    operationCooldown[rateLimitToken]
            ) {
                revert OperationCooldown();
            }
            lastOperationTime[rateLimitToken] = uint32(block.timestamp);
        }

        if (params.amount0Desired > 0) {
            if (_erc20Balance(token0) < params.amount0Desired)
                revert InsufficientBalance();
            token0.safeTransfer(SLIPSTREAM_HELPER, params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            if (_erc20Balance(token1) < params.amount1Desired)
                revert InsufficientBalance();
            token1.safeTransfer(SLIPSTREAM_HELPER, params.amount1Desired);
        }

        ISlipstreamPositionNFT.IncreaseLiquidityParams
            memory liqParams = ISlipstreamPositionNFT.IncreaseLiquidityParams({
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            });

        (
            uint256 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = ISlipstreamHelper(SLIPSTREAM_HELPER).increaseLiquidity(
                params.tokenId,
                liqParams
            );
        emit SlipstreamLiquidityIncreased(
            params.tokenId,
            liquidity,
            amount0,
            amount1
        );
    }

    /// @notice Decrease liquidity of Slipstream position
    function decreaseSlipstreamLiquidity(
        SlipstreamDecreaseParams calldata params
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        (address token0, address token1, , , , ) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).getPosition(params.tokenId);
        if (token0 == address(0) || token1 == address(0))
            revert InvalidAddress();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();
        ISlipstreamPositionNFT.DecreaseLiquidityParams
            memory decParams = ISlipstreamPositionNFT.DecreaseLiquidityParams({
                liquidity: params.liquidity,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            });

        (uint256 amount0, uint256 amount1) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).decreaseLiquidity(params.tokenId, decParams);
        emit SlipstreamLiquidityDecreased(
            params.tokenId,
            params.liquidity,
            amount0,
            amount1
        );
    }

    /// @notice Collect Slipstream fees to vault
    function collectSlipstreamFees(
        uint256 tokenId
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        (address token0, address token1, , , , ) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).getPosition(tokenId);
        if (token0 == address(0) || token1 == address(0))
            revert InvalidAddress();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        (uint256 amount0, uint256 amount1) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).collectFees(tokenId, address(this));
        emit SlipstreamFeesCollected(tokenId, amount0, amount1);
    }

    /// @notice Harvest Slipstream rewards from gauge
    function harvestSlipstreamRewards(
        address token0,
        address token1,
        uint24 fee
    ) external onlyOwner whenNotPaused nonReentrant returns (uint256 rewards) {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
        rewards = ISlipstreamHelper(SLIPSTREAM_HELPER).harvestRewards(
            positionHash
        );
        emit SlipstreamRewardsHarvested(positionHash, rewards);
    }

    /// @notice Stake Slipstream position NFT into gauge
    function stakeSlipstreamPosition(
        uint256 tokenId,
        address token0,
        address token1,
        uint24 fee
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
        ISlipstreamHelper(SLIPSTREAM_HELPER).stakePosition(
            tokenId,
            positionHash
        );
        emit SlipstreamPositionStaked(positionHash, tokenId);
    }

    /// @notice Unstake Slipstream position NFT from gauge
    function unstakeSlipstreamPosition(
        uint256 tokenId,
        address token0,
        address token1,
        uint24 fee
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        bytes32 positionHash = _slipstreamPositionHash(token0, token1, fee);
        ISlipstreamHelper(SLIPSTREAM_HELPER).unstakePosition(
            tokenId,
            positionHash
        );
        emit SlipstreamPositionUnstaked(positionHash, tokenId);
    }

    /// @notice Transfer Slipstream NFT to recipient (e.g., owner EOA)
    function transferSlipstreamPosition(
        uint256 tokenId,
        address recipient
    ) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        (address token0, address token1, , , , ) = ISlipstreamHelper(
            SLIPSTREAM_HELPER
        ).getPosition(tokenId);
        if (token0 == address(0) || token1 == address(0))
            revert InvalidAddress();
        if (tokenMapping[token0] == address(0)) revert TokenNotSupported();
        if (tokenMapping[token1] == address(0)) revert TokenNotSupported();

        ISlipstreamHelper(SLIPSTREAM_HELPER).transferPosition(
            tokenId,
            recipient
        );
        emit SlipstreamPositionTransferred(tokenId, recipient);
    }

    /// @notice Batch create LPs
    function batchCreateVeloLP(
        LPParams[] calldata params
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        for (uint256 i = 0; i < params.length; i++) {
            LPParams calldata p = params[i];
            if (tokenMapping[p.tokenA] == address(0))
                revert TokenNotSupported();
            if (_erc20Balance(p.tokenA) < p.amountA)
                revert InsufficientBalance();
            if (_erc20Balance(p.tokenB) < p.amountB)
                revert InsufficientBalance();
            p.tokenA.safeTransfer(VELO_HELPER, p.amountA);
            p.tokenB.safeTransfer(VELO_HELPER, p.amountB);
            IVelodromeHelper(VELO_HELPER).createLP(
                p.tokenA,
                p.tokenB,
                p.amountA,
                p.amountB,
                p.stable,
                p.stakeInGauge
            );
        }
    }

    /// @notice Harvest Velodrome rewards
    function harvestVelodromeRewards(
        bytes32 pairHash
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        IVelodromeHelper(VELO_HELPER).harvestRewards(pairHash);
    }

    /// @notice Harvest Velodrome fees
    function harvestVelodromeFees(
        address tokenA,
        address tokenB,
        bool stable
    ) external onlyOwner whenNotPaused nonReentrant {
        if (emergencyMode) revert EmsModeInit();
        IVelodromeHelper(VELO_HELPER).harvestFees(tokenA, tokenB, stable);
    }

    /// @notice Set Velodrome Voter
    function setVeloVoter(address _veloVoter) external onlyOwner {
        IVelodromeHelper(VELO_HELPER).setVeloVoter(_veloVoter);
    }

    /// @notice Get Velodrome gauge
    function getVeloGauge(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (address) {
        return IVelodromeHelper(VELO_HELPER).getGauge(tokenA, tokenB, stable);
    }

    /// @notice Get Velodrome LP balance (helper)
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable Stable pair flag
    /// @return balance LP token balance in helper
    function getVeloLPBalance(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256 balance) {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        return IVelodromeHelper(VELO_HELPER).getLPBalance(pairHash);
    }

    /// @notice Get staked Velodrome LP balance in gauge
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable Stable pair flag
    /// @return staked LP tokens staked in gauge
    function getVeloStakedLPBalance(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256 staked) {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        return IVelodromeHelper(VELO_HELPER).getStakedLPBalance(pairHash);
    }

    /// @notice Get total Velodrome LP balance (helper + staked)
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable Stable pair flag
    /// @return total Total LP tokens (helper + staked)
    function getVeloTotalLPBalance(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256 total) {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        return IVelodromeHelper(VELO_HELPER).getTotalLPBalance(pairHash);
    }

    /// @notice Unstake Velodrome LP from gauge
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable Stable pair flag
    /// @param amount Amount to unstake (0 = unstake all)
    function unstakeVeloLP(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amount
    ) external onlyOwner whenNotPaused nonReentrant {
        bytes32 pairHash = _veloPairHash(tokenA, tokenB, stable);
        IVelodromeHelper(VELO_HELPER).unstakeLP(pairHash, amount);
    }

    /// @notice Generate Velodrome pair hash (internal utils)
    function _veloPairHash(
        address tokenA,
        address tokenB,
        bool stable
    ) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1, stable));
    }

    /// @notice Generate Velodrome pair hash (public for testing)
    function veloPairHash(
        address tokenA,
        address tokenB,
        bool stable
    ) external pure returns (bytes32) {
        return _veloPairHash(tokenA, tokenB, stable);
    }

    function _slipstreamPositionHash(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1, fee));
    }

    function paused() public view returns (bool) {
        return _paused != 0;
    }

    /// @notice Emergency pause
    function pause() external onlyOwner {
        _paused = 1;
    }

    /// @notice Unpause
    function unpause() external onlyOwner {
        _paused = 0;
    }

    /// @dev Modifier to check pause state
    modifier whenNotPaused() {
        if (_paused != 0) revert();
        _;
    }

    /// @dev Modifier to check rate limits
    modifier rateLimitCheck(address token) {
        if (maxOperationsPerHour > 0) {
            uint32 currentHour = uint32(block.timestamp / 3600);
            if (operationsThisHour[currentHour] >= maxOperationsPerHour) {
                revert RateLimitExceeded();
            }
            operationsThisHour[currentHour]++;
        }
        if (operationCooldown[token] > 0) {
            if (
                block.timestamp <
                lastOperationTime[token] + operationCooldown[token]
            ) {
                revert OperationCooldown();
            }
            lastOperationTime[token] = uint32(block.timestamp);
        }
        _;
    }

    /// @dev Modifier to check withdrawal limits
    modifier withdrawalLimitCheck(address token, uint256 amount) {
        if (breakerActive) revert CircuitBreakerActive();
        if (maxDailyWithdrawals[token] > 0) {
            uint32 today = uint32(block.timestamp / 86400);
            uint128 todaysWithdrawals = dailyWithdrawals[token][today];
            if (
                todaysWithdrawals + uint128(amount) > maxDailyWithdrawals[token]
            ) {
                revert WithdrawalLimitExceeded();
            }
            dailyWithdrawals[token][today] =
                todaysWithdrawals +
                uint128(amount);
        }
        _;
    }

    /// @dev Modifier for emergency functions only
    modifier onlyInEmergency() {
        if (!emergencyMode) revert EmsModeInit();
        _;
    }

    /// @notice Refill gas balance
    function refillGas() external payable {
        if (msg.value == 0) revert();
        emit GasRefilled(msg.sender, msg.value);
    }

    function emsWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) {
            if (address(this).balance < amount) revert InsufficientBalance();
            SafeTransferLib.forceSafeTransferETH(to, amount);
        } else {
            uint256 balance = _erc20Balance(token);
            if (balance < amount) revert InsufficientBalance();
            SafeTransferLib.safeTransfer(token, to, amount);
        }

        emit EmergencyWithdrawal(token, to, amount, msg.sender);
    }

    function emsWithdrawFromTydro(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        bytes32 withdrawArgs = amount == 0
            ? IL2Encoder(L2_ENCODER).encodeWithdrawParams(
                token,
                type(uint256).max
            )
            : IL2Encoder(L2_ENCODER).encodeWithdrawParams(token, amount);

        uint256 withdrawn = IL2Pool(TYDRO_POOL).withdraw(withdrawArgs);
        if (withdrawn == 0) revert InsufficientYield();

        SafeTransferLib.safeTransfer(token, to, withdrawn);
        emit EmergencyTydroWithdrawal(token, to, withdrawn, msg.sender);
    }

    function activateEmsMode() external onlyOwner {
        emergencyMode = true;
        emit EmergencyModeActivated(msg.sender);
    }

    function deactivateEmsMode() external onlyOwner {
        emergencyMode = false;
        emit EmergencyModeDeactivated(msg.sender);
    }

    function activateBreaker() external onlyOwner {
        breakerActive = true;
        emit CircuitBreakerActivated(msg.sender);
    }

    function deactivateBreaker() external onlyOwner {
        breakerActive = false;
        emit CircuitBreakerDeactivated(msg.sender);
    }

    /// @notice Receive ETH for gas
    receive() external payable {
        emit GasRefilled(msg.sender, msg.value);
    }

    event VaultInitialized(
        address tydroPool,
        address l2Encoder,
        address acrossSpokePool,
        address l1Recipient
    );
    event TokenMappingSet(address indexed l2Token, address indexed l1Token);
    event L1RecipientSet(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    event Deposited(
        address indexed token,
        uint256 amount,
        address indexed depositor
    );
    event YieldHarvested(address indexed token, uint256 amount);
    event YieldCompounded(address indexed token, uint256 amount);
    event YieldBridged(address indexed token, uint256 amount);
    event AutoHarvested(address indexed token, bool success);
    event DefaultCompoundPercentUpdated(uint8 oldPercent, uint8 newPercent);
    event MinYieldThresholdUpdated(uint64 oldThreshold, uint64 newThreshold);
    event GasRefilled(address indexed refiller, uint256 amount);
    event MinGasBalanceUpdated(uint128 oldMin, uint128 newMin);
    event AutoDeposited(
        address indexed token,
        uint256 amount,
        address indexed caller,
        bool usedSmartAllocation
    );
    event AutoDepositSkipped(
        address indexed token,
        uint256 currentBalance,
        uint256 depositedAmount,
        address indexed caller
    );
    event YieldUpdated(address indexed token, uint256 yield);
    event YieldAllocatorSet(address indexed allocator);
    event SmartRebalanced(address indexed token, uint256 amount);
    event SmartCompounded(address indexed token, uint256 amount);
    event SlippageUpdated(uint64 oldSlippage, uint64 newSlippage);
    event AutoGasRefillUpdated(uint64 oldBps, uint64 newBps);
    event HarvestStep(address indexed token, string step);
    event BridgeError(
        address indexed token,
        bytes4 errorSelector,
        uint256 bridgeAmount,
        uint256 minAmountOut
    );

    event EmergencyWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount,
        address indexed caller
    );
    event EmergencyTydroWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount,
        address indexed caller
    );
    event EmergencyModeActivated(address indexed activator);
    event EmergencyModeDeactivated(address indexed deactivator);
    event CircuitBreakerActivated(address indexed activator);
    event CircuitBreakerDeactivated(address indexed deactivator);

    event MaxOperationsUpdated(uint8 oldMax, uint8 newMax);
    event OperationCooldownUpdated(
        address indexed token,
        uint32 oldCooldown,
        uint32 newCooldown
    );
    event MaxDailyWithdrawalUpdated(
        address indexed token,
        uint128 oldMax,
        uint128 newMax
    );
    event MaxDepositUpdated(
        address indexed token,
        uint128 oldMax,
        uint128 newMax
    );
    event MulticallExecuted(uint256 callCount);
    event BatchYieldUpdated(uint256 tokenCount);
    event BatchHarvestCompleted(uint256 tokenCount);
    event BatchHarvestSuccess(address indexed token, uint256 index);
    event BatchHarvestFailed(address indexed token, uint256 index);

    event VelodromeRouterSet(address indexed router);
    event VelodromeVoterSet(address indexed oldVoter, address indexed newVoter);
    event VelodromeLPCreated(
        address indexed tokenA,
        address indexed tokenB,
        bool stable,
        uint256 liquidity,
        bool staked
    );
    event VelodromeLPStaked(
        bytes32 indexed pairHash,
        address indexed gauge,
        uint256 amount
    );
    event VelodromeRewardsHarvested(
        bytes32 indexed pairHash,
        address indexed gauge,
        uint256 amount
    );
    event VelodromeFeesHarvested(
        bytes32 indexed pairHash,
        address indexed pair,
        uint256 fee0,
        uint256 fee1
    );
    event VelodromeLPSentToOwner(
        address indexed pair,
        uint256 liquidity,
        address indexed owner
    );
    event SlipstreamGaugeSet(
        address indexed token0,
        address indexed token1,
        uint24 fee,
        address gauge
    );
    event SlipstreamPositionCreated(
        uint256 indexed tokenId,
        address indexed token0,
        address indexed token1,
        uint24 fee,
        bool staked
    );
    event SlipstreamLiquidityIncreased(
        uint256 indexed tokenId,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event SlipstreamLiquidityDecreased(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event SlipstreamFeesCollected(
        uint256 indexed tokenId,
        uint256 amount0,
        uint256 amount1
    );
    event SlipstreamRewardsHarvested(
        bytes32 indexed positionHash,
        uint256 rewards
    );
    event SlipstreamPositionStaked(
        bytes32 indexed positionHash,
        uint256 indexed tokenId
    );
    event SlipstreamPositionUnstaked(
        bytes32 indexed positionHash,
        uint256 indexed tokenId
    );
    event SlipstreamPositionTransferred(
        uint256 indexed tokenId,
        address indexed recipient
    );

    /// @notice Batch operation events
    event BatchSlipstreamFeesCollected(uint256 positionCount);
    event BatchSlipstreamRewardsHarvested(uint256 positionCount);
    event FullYieldCycleCompleted(
        address indexed token,
        uint256 indexed tokenId,
        uint256 zapAmount
    );
}
