// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IL2Pool} from "./interfaces/IL2Pool.sol";
import {IL2Encoder} from "./interfaces/IL2Encoder.sol";
import {IAToken} from "./interfaces/ITydroAAVE.sol";
import {IRelayDepository} from "./interfaces/IRelay.sol";

/// @title BundledYieldVaultV2_RELAY
/// @notice Private treasury L2 (Ink) vault for yield farming and bridging yield back to L1 via Relay Protocol
/// @author sorbet/pepecoin core
contract BundledYieldVaultV2_RELAY is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @dev Tydro pool contract address
    address public immutable TYDRO_POOL;
    /// @dev Relay Depository contract address (Ink L2)
    address public immutable RELAY_DEPOSITORY;
    /// @dev L1 chain ID (Ethereum mainnet)
    uint256 public constant L1_CHAIN_ID = 1;
    /// @dev L1 recipient address (L1Depositor)
    address public l1Recipient;
    /// @dev Mapping from L2 token address to L1 token address
    mapping(address => address) public tokenMapping;
    /// @dev Minimum gas balance required (in wei)
    uint128 public minGasBalance = 0.05 ether;
    /// @dev Maximum bridge fee (basis points, e.g., 100 = 1%)
    uint64 public maxBridgeFeeBps = 100; // 1% default
    /// @dev Auto gas refill percentage (basis points, e.g., 50 = 0.5%)
    uint64 public autoGasRefillBps = 50; // 0.5% default
    /// @dev Bridge deadline (hours)
    uint64 public bridgeDeadlineHours = 24; // 24 hours default
    /// @dev Pause flag - packed into single storage slot for gas efficiency
    uint256 private _paused;

    /// @dev Token status tracking - packed for gas efficiency
    struct TokenStatus {
        uint128 depositedAmount;
        uint128 currentBalance;
        uint128 yieldAvailable;
        uint32 lastUpdate;
    }

    /// @dev Mapping from L2 token address to token status
    mapping(address => TokenStatus) public tokenStatus;
    /// @dev Mapping from L2 token address to aToken address
    mapping(address => address) private _aTokens;
    /// @dev L2 encoder contract (compressed calldata helper)
    address public immutable L2_ENCODER;

    /// @param _tydroPool Address of Tydro lending pool
    /// @param _relayDepository Address of Relay Depository on Ink L2
    /// @param _l1Recipient Address of L1 recipient (L1Depositor)
    constructor(address _tydroPool, address _l2Encoder, address _relayDepository, address _l1Recipient) {
        if (_tydroPool == address(0) || _relayDepository == address(0) || _l2Encoder == address(0)) revert InvalidAddress();
        TYDRO_POOL = _tydroPool;
        RELAY_DEPOSITORY = _relayDepository;
        L2_ENCODER = _l2Encoder;
        l1Recipient = _l1Recipient;
        _initializeOwner(msg.sender);
    }

    /// @dev Modifier to check state
    modifier whenNotPaused() {
        if (_paused != 0) revert();
        _;
    }

    /// @notice Auto-deposit available bridged funds to Tydro (anyone can call - keeper-friendly)
    /// @param token L2 token address
    function depositAvailable(address token) external whenNotPaused nonReentrant {
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        TokenStatus storage status = tokenStatus[token];
        uint256 currentBalance = _erc20Balance(token);
        uint256 depositedAmount = status.depositedAmount;
        if (currentBalance <= depositedAmount) {
            return;
        }
        
        uint256 newAmount = currentBalance - depositedAmount;
        _depositToTydro(token, newAmount);
        
        emit AutoDeposited(token, newAmount, msg.sender);
    }
    
    /// @notice Deposit tokens to Tydro pool (Owner only)
    /// @param token L2 token address
    /// @param amount Amount to deposit
    function deposit(address token, uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (tokenMapping[token] == address(0)) revert TokenNotSupported();
        uint256 balanceBefore = _erc20Balance(token);
        if (balanceBefore < amount) revert InsufficientBalance();
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        ///deposit to Tydro
        _depositToTydro(token, amount);

        emit Deposited(token, amount);
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

        bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(token, amount, 0);
        try IL2Pool(TYDRO_POOL).supply(supplyArgs) {
            emit HarvestStep(token, "deposit_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "deposit_failed");
            if (reason.length >= 4) {
                bytes4 selector = bytes4(reason);
                if (selector == bytes4(0xa4937508)) {
                    revert DepositFailed(); // NotEnoughAvailableLiquidity
                }
            }
            revert DepositFailed();
        }
        if (_aTokens[token] == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
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
        
        address aToken = _aTokens[token];
        if (aToken == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
            aToken = aTokenAddress;
        }
        uint256 currentBalance = aToken == address(0) ? 0 : IAToken(aToken).balanceOf(address(this));
        uint256 deposited = status.depositedAmount;
        
        ///calculate yield = balance - deposited amount
        if (currentBalance > deposited) {
            return currentBalance - deposited;
        }
        return 0;
    }

    /// @notice Update yield available (can be called by anyone to refresh)
    function updateYield(address token) external {
        _updateYield(token);
    }
    
    /// @notice Internal function to update yield (avoids external call overhead)
    function _updateYield(address token) internal {
        TokenStatus storage status = tokenStatus[token];
        address aToken = _aTokens[token];
        if (aToken == address(0)) {
            (, , , , , , , , address aTokenAddress, , , , , , ) = IL2Pool(TYDRO_POOL).getReserveData(token);
            _aTokens[token] = aTokenAddress;
            aToken = aTokenAddress;
        }
        uint256 currentBalance = aToken == address(0) ? 0 : IAToken(aToken).balanceOf(address(this));
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

    /// @notice Harvest yield and bridge to L1 treasury (Owner only)
    /// @param token L2 token address
    /// @param compoundPercent Percentage to compound (0-100), rest goes to L1
    /// @param customFeeBps Optional custom fee (0 = use default)
    /// @param minBridgeAmount Minimum amount to receive on L1 (0 = calculated from fee)
    function harvestAndBridge(
        address token,
        uint8 compoundPercent,
        uint64 customFeeBps,
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
        
        bool needsGasRefill = address(this).balance < minGasBalance;
        if (needsGasRefill && autoGasRefillBps == 0) revert InsufficientGas();
        _updateYield(token);
        emit HarvestStep(token, "yield_updated");

        TokenStatus storage status = tokenStatus[token];
        uint256 principal = status.depositedAmount;
        if (principal == 0) revert InsufficientYield();

        bytes32 withdrawArgs = IL2Encoder(L2_ENCODER).encodeWithdrawParams(token, type(uint256).max);
        uint256 withdrawn;
        try IL2Pool(TYDRO_POOL).withdraw(withdrawArgs) returns (uint256 amountWithdrawn) {
            withdrawn = amountWithdrawn;
            emit HarvestStep(token, "withdraw_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "withdraw_failed");
            if (reason.length >= 4) {
                bytes4 selector = bytes4(reason);
                if (selector == bytes4(0xa4937508)) {
                    revert WithdrawFailed(); // NotEnoughAvailableLiquidity
                }
            }
            revert WithdrawFailed();
        }
        if (withdrawn <= principal) revert InsufficientYield();

        uint256 yieldAmount = withdrawn - principal;
        status.yieldAvailable = 0;
        uint256 compoundAmount;
        uint256 bridgeAmount;
        assembly {
            compoundAmount := mul(yieldAmount, compoundPercent)
            compoundAmount := div(compoundAmount, 100)
            bridgeAmount := sub(yieldAmount, compoundAmount)
        }

        uint256 resupplyAmount = principal + compoundAmount;
        uint256 balanceBeforeResupply = _erc20Balance(token);
        if (balanceBeforeResupply < resupplyAmount) revert InsufficientBalance();
        SafeTransferLib.safeApprove(token, TYDRO_POOL, 0);
        SafeTransferLib.safeApprove(token, TYDRO_POOL, resupplyAmount);
        
        bytes32 resupplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(token, resupplyAmount, 0);
        try IL2Pool(TYDRO_POOL).supply(resupplyArgs) {
            status.depositedAmount = uint128(resupplyAmount);
            status.currentBalance = uint128(resupplyAmount);
            status.lastUpdate = uint32(block.timestamp);
            emit HarvestStep(token, "resupply_success");
        } catch (bytes memory reason) {
            emit HarvestStep(token, "resupply_failed");
            revert DepositFailed();
        }
        if (compoundAmount > 0) {
            emit YieldCompounded(token, compoundAmount);
        }

        emit YieldHarvested(token, yieldAmount);
        ///bridge to L1 via Relay
        if (bridgeAmount > 0) {
            ///auto-refill if needed
            uint256 actualBridgeAmount = bridgeAmount;
            if (needsGasRefill && autoGasRefillBps > 0) {
                uint256 gasRefillAmount = (bridgeAmount * autoGasRefillBps) / 10000;
                if (gasRefillAmount > 0.01 ether) {
                    gasRefillAmount = 0.01 ether;
                }
                if (gasRefillAmount <= bridgeAmount) {
                    actualBridgeAmount -= gasRefillAmount;
                    emit GasRefilled(address(this), gasRefillAmount);
                }
            }
            
            if (actualBridgeAmount > 0) {
                uint64 feeBps = customFeeBps > 0 ? customFeeBps : maxBridgeFeeBps;
                if (feeBps > 1000) revert InvalidSlippage(); ///Max 10%
                
                uint256 calculatedMaxFee = (actualBridgeAmount * feeBps) / 10000;
                if (minBridgeAmount > 0) {
                    uint256 expectedAmount = actualBridgeAmount - calculatedMaxFee;
                    if (minBridgeAmount > expectedAmount) revert SlippageTooHigh();
                }
                
                uint256 deadline = block.timestamp + (bridgeDeadlineHours * 1 hours);
                uint256 balanceBeforeBridge = _erc20Balance(token);
                if (balanceBeforeBridge < actualBridgeAmount) revert InsufficientBalance();
                
                uint256 currentAllowance = _erc20Allowance(token, RELAY_DEPOSITORY);
                if (currentAllowance < actualBridgeAmount) {
                    SafeTransferLib.safeApprove(token, RELAY_DEPOSITORY, 0);
                    SafeTransferLib.safeApprove(token, RELAY_DEPOSITORY, actualBridgeAmount);
                }
                
                emit HarvestStep(token, "bridge_attempting");
                try IRelayDepository(RELAY_DEPOSITORY).deposit(
                    L1_CHAIN_ID,
                    l1Recipient,
                    token,
                    actualBridgeAmount,
                    calculatedMaxFee,
                    deadline
                ) returns (bytes32 depositId) {
                    emit YieldBridged(token, actualBridgeAmount);
                    emit DepositInitiated(depositId, token, actualBridgeAmount);
                    emit HarvestStep(token, "bridge_success");
                } catch (bytes memory reason) {
                    emit HarvestStep(token, "bridge_failed");
                    if (reason.length >= 4) {
                        bytes4 selector = bytes4(reason);
                        emit BridgeError(token, selector, actualBridgeAmount, calculatedMaxFee);
                    }
                    revert BridgeFailed();
                }
            }
        }
    }
    
    /// @notice Auto-deposit and harvest in one call (Owner only)
    /// @param token L2 token address
    /// @param compoundPercent Percentage of yield to compound (0-100)
    /// @param customFeeBps Custom fee tolerance in basis points (0 = use default)
    /// @param minBridgeAmount Minimum amount to receive on L1 (0 = calculate from fee)
    /// @dev First auto-deposits any available bridged funds, then harvests yield
    function depositAndHarvest(
        address token,
        uint8 compoundPercent,
        uint64 customFeeBps,
        uint256 minBridgeAmount
    )
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        ///auto-deposit any available bridged funds (call via this to access external function)
        this.depositAvailable(token);
        ///harvest and bridge yield (call via this to access external function)
        this.harvestAndBridge(token, compoundPercent, customFeeBps, minBridgeAmount);
    }

    /// @notice Refill gas manually (payable)
    function refillGas() external payable {
        if (msg.value == 0) revert();
        emit GasRefilled(msg.sender, msg.value);
    }

    /// @notice Emergency withdraw (Owner only)
    /// @param token Token address (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            SafeTransferLib.forceSafeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }

    /// @notice Receive ETH (for gas refills)
    receive() external payable {
        emit GasRefilled(msg.sender, msg.value);
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
    function _erc20Allowance(address token, address spender) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("allowance(address,address)", address(this), spender)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    /// @notice Set token mapping (L2 token => L1 token)
    function setTokenMapping(address l2Token, address l1Token) external onlyOwner {
        if (l2Token == address(0) || l1Token == address(0)) revert InvalidAddress();
        tokenMapping[l2Token] = l1Token;
        emit TokenMappingSet(l2Token, l1Token);
    }

    /// @notice Set L1 recipient address
    function setL1Recipient(address _l1Recipient) external onlyOwner {
        if (_l1Recipient == address(0)) revert InvalidAddress();
        address oldRecipient = l1Recipient;
        l1Recipient = _l1Recipient;
        emit L1RecipientSet(oldRecipient, _l1Recipient);
    }

    /// @notice Set minimum gas balance
    function setMinGasBalance(uint128 _minGasBalance) external onlyOwner {
        uint128 oldMin = minGasBalance;
        minGasBalance = _minGasBalance;
        emit MinGasBalanceUpdated(oldMin, _minGasBalance);
    }

    /// @notice Set maximum bridge fee (basis points)
    function setMaxBridgeFee(uint64 _feeBps) external onlyOwner {
        if (_feeBps > 1000) revert InvalidSlippage(); // Max 10%
        uint64 oldFee = maxBridgeFeeBps;
        maxBridgeFeeBps = _feeBps;
        emit MaxBridgeFeeUpdated(oldFee, _feeBps);
    }

    /// @notice Set auto-gas refill percentage (basis points)
    function setAutoGasRefill(uint64 _autoGasRefillBps) external onlyOwner {
        if (_autoGasRefillBps > 500) revert InvalidSlippage(); // Max 5%
        uint64 oldBps = autoGasRefillBps;
        autoGasRefillBps = _autoGasRefillBps;
        emit AutoGasRefillUpdated(oldBps, _autoGasRefillBps);
    }

    /// @notice Set bridge deadline (hours)
    function setBridgeDeadline(uint64 _hours) external onlyOwner {
        if (_hours == 0 || _hours > 168) revert InvalidSlippage(); // Max 1 week
        bridgeDeadlineHours = _hours;
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

    /// @notice Events
    event HarvestStep(address indexed token, string step);
    event TokenMappingSet(address indexed l2Token, address indexed l1Token);
    event L1RecipientSet(address indexed oldRecipient, address indexed newRecipient);
    event Deposited(address indexed token, uint256 amount);
    event YieldHarvested(address indexed token, uint256 amount);
    event YieldCompounded(address indexed token, uint256 amount);
    event YieldBridged(address indexed token, uint256 amount);
    event GasRefilled(address indexed refiller, uint256 amount);
    event MinGasBalanceUpdated(uint128 oldMin, uint128 newMin);
    event YieldUpdated(address indexed token, uint256 yield);
    event MaxBridgeFeeUpdated(uint64 oldFee, uint64 newFee);
    event AutoGasRefillUpdated(uint64 oldBps, uint64 newBps);
    event DepositInitiated(bytes32 indexed depositId, address indexed token, uint256 amount);
    event AutoDeposited(address indexed token, uint256 amount, address indexed caller);
    event BridgeError(address indexed token, bytes4 errorSelector, uint256 bridgeAmount, uint256 maxFee);
}

