// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ITydroPool} from "./interfaces/ITydro.sol";
import {ISpokePool} from "./interfaces/IAcross.sol";

/// @title BundledYieldVaultV2
/// @notice Private treasury L2 (Ink) vault for yield farming and bridging yield back to L1
contract BundledYieldVaultV2 is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    error TokenNotSupported();
    error L1RecipientNotSet();
    error InsufficientGas();
    error InsufficientYield();
    error DepositFailed();
    error WithdrawFailed();
    error InvalidCompoundPercent();
    error InvalidAddress();
    error SlippageTooHigh();
    error InvalidSlippage();

    /// @dev Tydro pool contract address
    address public immutable TYDRO_POOL;

    /// @dev Across SpokePool contract address
    address public immutable ACROSS_SPOKE_POOL;

    /// @dev L1 chain ID (Ethereum mainnet)
    uint256 public constant L1_CHAIN_ID = 1;

    /// @dev L1 recipient address (L1Depositor)
    address public l1Recipient;

    /// @dev Mapping from L2 token address to L1 token address
    mapping(address => address) public tokenMapping;

    /// @dev Minimum gas balance required (in wei)
    uint128 public minGasBalance = 0.05 ether;
    
    /// @dev Default slippage for bridging (basis points, e.g., 100 = 1%)
    uint64 public defaultSlippageBps = 100;
    
    /// @dev Auto-refill gas from bridge amount (basis points, e.g., 50 = 0.5%)
    uint64 public autoGasRefillBps = 50;

    /// @dev Pause flag - packed into single storage slot for gas efficiency
    uint256 private _paused;

    /// @dev Packed struct (4 slots → 1 slot)
    struct TokenStatus {
        uint128 depositedAmount; ///Amount deposited to Tydro
        uint128 currentBalance;  ///Current balance in Tydro
        uint128 yieldAvailable;  ///Accumulated yield
        uint32 lastUpdate;       ///Last update timestamp (block.timestamp truncated)
    }

    mapping(address => TokenStatus) public tokenStatus;

    /// @param _tydroPool Tydro pool contract address
    /// @param _acrossSpokePool Across SpokePool contract address
    /// @param _l1Recipient Initial L1 recipient address
    constructor(address _tydroPool, address _acrossSpokePool, address _l1Recipient) {
        if (_tydroPool == address(0) || _acrossSpokePool == address(0)) revert InvalidAddress();
        TYDRO_POOL = _tydroPool;
        ACROSS_SPOKE_POOL = _acrossSpokePool;
        l1Recipient = _l1Recipient;
        _initializeOwner(msg.sender);
    }

    /// @notice Set the L1 token address for a given L2 token
    function setTokenMapping(address l2Token, address l1Token) external onlyOwner {
        if (l2Token == address(0) || l1Token == address(0)) revert InvalidAddress();
        tokenMapping[l2Token] = l1Token;
        emit TokenMappingSet(l2Token, l1Token);
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
    
    /// @notice Set default slippage for bridging (basis points)
    function setDefaultSlippage(uint64 _slippageBps) external onlyOwner {
        if (_slippageBps > 1000) revert InvalidSlippage();///Max 10%
        uint64 oldSlippage = defaultSlippageBps;
        defaultSlippageBps = _slippageBps;
        emit SlippageUpdated(oldSlippage, _slippageBps);
    }
    
    /// @notice Set auto-gas refill percentage (basis points)
    function setAutoGasRefill(uint64 _autoGasRefillBps) external onlyOwner {
        if (_autoGasRefillBps > 500) revert InvalidSlippage();///Max 5%
        uint64 oldBps = autoGasRefillBps;
        autoGasRefillBps = _autoGasRefillBps;
        emit AutoGasRefillUpdated(oldBps, _autoGasRefillBps);
    }

    /// @notice Check if contract is paused
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

    /// @notice Deposit treasury tokens to Tydro pool (Owner only - Private Treasury)
    function deposit(address token, uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(token, TYDRO_POOL, amount);

        try ITydroPool(TYDRO_POOL).deposit(token, amount) returns (uint256 shares) {
            if (shares == 0) revert DepositFailed();
        } catch {
            revert DepositFailed();
        }
        TokenStatus storage status = tokenStatus[token];
        unchecked {
            status.depositedAmount += uint128(amount);
            status.currentBalance += uint128(amount);
            status.lastUpdate = uint32(block.timestamp);
        }

        emit Deposited(token, amount);
    }

    /// @notice Get current status for a token
    function getStatus(address token)
        external
        view
        returns (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, uint256 gasBalance)
    {
        TokenStatus storage status = tokenStatus[token];
        return (
            status.depositedAmount,
            status.currentBalance,
            status.yieldAvailable,
            address(this).balance
        );
    }

    /// @notice Check available yield for a token (reads from Tydro pool)
    function getYieldAvailable(address token) external view returns (uint256 yield) {
        TokenStatus storage status = tokenStatus[token];
        (, bytes memory returnData) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        uint256 currentBalance = returnData.length == 0 ? 0 : abi.decode(returnData, (uint256));
        uint256 deposited = status.depositedAmount;
        if (currentBalance > deposited) {
            return currentBalance - deposited;
        }
        return 0;
    }

    /// @notice Update yield available (can be called by anyone to refresh)
    function updateYield(address token) external {
        TokenStatus storage status = tokenStatus[token];
        (, bytes memory returnData) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        uint256 currentBalance = returnData.length == 0 ? 0 : abi.decode(returnData, (uint256));
        uint256 deposited = status.depositedAmount;
        status.currentBalance = uint128(currentBalance);
        status.lastUpdate = uint32(block.timestamp);
        
        if (currentBalance > deposited) {
            uint256 yield = currentBalance - deposited;
            status.yieldAvailable = uint128(yield);
            emit YieldUpdated(token, yield);
        } else {
            status.yieldAvailable = 0;
            emit YieldUpdated(token, 0);
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
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        if (l1Recipient == address(0)) revert L1RecipientNotSet();
        if (compoundPercent > 100) revert InvalidCompoundPercent();
        
       ///if gas islow, we'll autorefill from bridge amt
        bool needsGasRefill = address(this).balance < minGasBalance;
        if (needsGasRefill && autoGasRefillBps == 0) revert InsufficientGas();
        this.updateYield(token);

        TokenStatus storage status = tokenStatus[token];
        uint256 yield = status.yieldAvailable;
        if (yield == 0) revert InsufficientYield();
        try ITydroPool(TYDRO_POOL).withdraw(token, yield) {
           ///Withdrawal successful
        } catch {
            revert WithdrawFailed();
        }
        unchecked {
            status.yieldAvailable = 0;
            status.currentBalance -= uint128(yield);
        }

        emit YieldHarvested(token, yield);
        uint256 compoundAmount;
        uint256 bridgeAmount;
        assembly {
            compoundAmount := mul(yield, compoundPercent)
            compoundAmount := div(compoundAmount, 100)
            bridgeAmount := sub(yield, compoundAmount)
        }
       ///Compound back to pool
        if (compoundAmount > 0) {
            SafeTransferLib.safeApprove(token, TYDRO_POOL, compoundAmount);
            try ITydroPool(TYDRO_POOL).deposit(token, compoundAmount) returns (uint256 shares) {
                if (shares > 0) {
                    unchecked {
                        status.depositedAmount += uint128(compoundAmount);
                        status.currentBalance += uint128(compoundAmount);
                        status.lastUpdate = uint32(block.timestamp);
                    }
                    emit YieldCompounded(token, compoundAmount);
                }
            } catch {}
        }
       ///Bridge to L1 via Across
        if (bridgeAmount > 0) {
            address l1Token = tokenMapping[token];
            uint64 slippageBps = customSlippageBps > 0 ? customSlippageBps : defaultSlippageBps;
            if (slippageBps > 1000) revert InvalidSlippage();///Max 10%
            
           ///Calculate minimum output (use provided minBridgeAmount if > 0)
            uint256 minAmountOut;
            if (minBridgeAmount > 0) {
                uint256 expectedAmount = (bridgeAmount * (10000 - slippageBps)) / 10000;
                if (minBridgeAmount > expectedAmount) revert SlippageTooHigh();
                minAmountOut = minBridgeAmount;
            } else {
                minAmountOut = (bridgeAmount * (10000 - slippageBps)) / 10000;
            }
            
           ///Auto-refill gas if needed (deduct from bridge amount)
            uint256 actualBridgeAmount = bridgeAmount;
            if (needsGasRefill && autoGasRefillBps > 0) {
                uint256 gasRefillAmount = (bridgeAmount * autoGasRefillBps) / 10000;
                if (gasRefillAmount > 0.01 ether) {
                    gasRefillAmount = 0.01 ether;
                }
                if (gasRefillAmount <= bridgeAmount) {
                    actualBridgeAmount -= gasRefillAmount;
                   ///Gas is automatically added to contract balance via this transaction
                    emit GasRefilled(address(this), gasRefillAmount);
                }
            }
            if (actualBridgeAmount > 0) {
               ///Recalculate minAmountOut for reduced bridge amount
                if (minBridgeAmount == 0) {
                    minAmountOut = (actualBridgeAmount * (10000 - slippageBps)) / 10000;
                } else {
                   ///Proportionally reduce minAmountOut
                    minAmountOut = (minAmountOut * actualBridgeAmount) / bridgeAmount;
                }
                SafeTransferLib.safeApprove(token, ACROSS_SPOKE_POOL, actualBridgeAmount);
                
               ///Bridge via Across SpokePool
                bytes memory message = abi.encode(l1Recipient);
                
                try ISpokePool(ACROSS_SPOKE_POOL).depositNow(
                    address(this),       ///depositor
                    l1Recipient,         ///recipient
                    token,                ///inputToken (L2)
                    l1Token,             ///outputToken (L1)
                    actualBridgeAmount,  ///inputAmount (after gas deduction)
                    minAmountOut,        ///outputAmount (minimum)
                    L1_CHAIN_ID,         ///destinationChainId
                    0,                   ///relayerFeePct (0 for now)
                    uint32(block.timestamp),///quoteTimestamp
                    message,             ///message
                    0                    ///maxCount (0 = no limit)
                ) {
                    emit YieldBridged(token, actualBridgeAmount);
                } catch {
                    revert WithdrawFailed();
                }
            }
        }
    }

    /// @notice Refill gas balance (accept ETH)
    function refillGas() external payable {
        if (msg.value == 0) revert();
        emit GasRefilled(msg.sender, msg.value);
    }

    /// @notice Emergency withdraw (owner only)
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            SafeTransferLib.forceSafeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }

    /// @notice Receive ETH for gas
    receive() external payable {
        emit GasRefilled(msg.sender, msg.value);
    }

    event TokenMappingSet(address indexed l2Token, address indexed l1Token);
    event L1RecipientSet(address indexed oldRecipient, address indexed newRecipient);
    event Deposited(address indexed token, uint256 amount);
    event YieldHarvested(address indexed token, uint256 amount);
    event YieldCompounded(address indexed token, uint256 amount);
    event YieldBridged(address indexed token, uint256 amount);
    event GasRefilled(address indexed refiller, uint256 amount);
    event MinGasBalanceUpdated(uint128 oldMin, uint128 newMin);
    event YieldUpdated(address indexed token, uint256 yield);
    event SlippageUpdated(uint64 oldSlippage, uint64 newSlippage);
    event AutoGasRefillUpdated(uint64 oldBps, uint64 newBps);
}
