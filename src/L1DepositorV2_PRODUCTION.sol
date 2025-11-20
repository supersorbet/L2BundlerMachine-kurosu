// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IHubPool} from "./interfaces/IAcross.sol";

/// @title L1DepositorV2_
/// @notice Private treasury L1 contract for depositing tokens to L2 (Ink) via Across Bridge
/// @author sorbet/pepecoin core
contract L1DepositorV2_PROD is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    /// @dev Error for token not supported
    error TokenNotSupported();
    /// @dev Error for L2 vault not set
    error L2VaultNotSet();
    /// @dev Error for insufficient amount
    error InsufficientAmount();
    /// @dev Error for slippage too high
    error SlippageTooHigh();
    error UnauthorizedYieldReceiver();
    /// @dev Error for invalid address
    error InvalidAddress();

    /// @dev Across HubPool contract address
    address public immutable HUB_POOL;
    /// @dev Destination chain ID for Ink L2
    uint256 public immutable DESTINATION_CHAIN_ID;
    /// @dev L2 vault address (recipient on Ink L2)
    address public l2Vault;
    /// @dev Mapping from L1 token address to L2 token address
    mapping(address => address) public tokenMapping;
    /// @dev Maximum slippage allowed (basis points, e.g., 50 = 0.5%)
    uint64 public maxSlippageBps = 50;
    /// @dev Minimum deposit amount to prevent dust attacks
    uint128 public minDepositAmount = 1000;
    /// @dev Track total deposits per token
    mapping(address => uint256) public totalDeposits;

    uint256 private _paused;
    /// @dev Track yield received from L2 per token
    mapping(address => uint256) public yieldBalance;
    /// @dev Track yield recipients (for access control)
    mapping(address => bool) public authorizedYieldReceivers;

    /// @param _hubPool Across HubPool contract address
    /// @param _l2Vault Initial L2 vault address
    /// @param _destinationChainId Ink L2 chain ID
    constructor(address _hubPool, address _l2Vault, uint256 _destinationChainId) {
        if (_hubPool == address(0)) revert InvalidAddress();
        HUB_POOL = _hubPool;
        l2Vault = _l2Vault;
        DESTINATION_CHAIN_ID = _destinationChainId;
        _initializeOwner(msg.sender);
    }

    /// @dev Modifier to check pause state
    modifier whenNotPaused() {
        if (_paused != 0) revert();
        _;
    }

    /// @notice Deposit treasury tokens to L2 via Across Bridge (Owner only - Private Treasury)
    /// @param token L1 token address (e.g., USDT)
    /// @param amount Amount to deposit
    /// @param minAmount Minimum amount expected on L2 (slippage protection)
    function depositToL2(address token, uint256 amount, uint256 minAmount)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        address l2Token = tokenMapping[token];
        if (l2Token == address(0)) revert TokenNotSupported();
        if (l2Vault == address(0)) revert L2VaultNotSet();
        if (amount < minDepositAmount) revert InsufficientAmount();
        if (minAmount > 0) {
            uint256 expectedAmount = (amount * (10000 - maxSlippageBps)) / 10000;
            if (minAmount > expectedAmount) revert SlippageTooHigh();
        }
       ///Transfer tokens from treasury (owner must approve first)
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(token, HUB_POOL, amount);
       ///Bridge via Across HubPool
        bytes memory message = abi.encode(l2Vault);
        IHubPool(HUB_POOL).deposit(
            l2Vault,             ///recipient
            token,               ///inputToken (L1)
            l2Token,             ///outputToken (L2)
            amount,              ///inputAmount
            minAmount,           ///outputAmount (minimum)
            DESTINATION_CHAIN_ID,///destinationChainId
            address(0),           ///exclusiveRelayer (none)
            block.timestamp,     ///quoteTimestamp
            message              ///message (contains l2Vault)
        );

        unchecked {
            totalDeposits[token] += amount;
        }

        emit DepositToL2(token, msg.sender, amount, minAmount);
    }

    /// @notice Receive yield from L2 (called by authorized relayers)
    /// @param token Token address
    /// @param amount Amount received
    function receiveYield(address token, uint256 amount) external {
        if (!authorizedYieldReceivers[msg.sender]) revert UnauthorizedYieldReceiver();
        if (token == address(0) || amount == 0) revert InvalidAddress();
        unchecked {
            yieldBalance[token] += amount;
        }
        emit YieldReceived(token, amount);
    }

    /// @notice Withdraw accumulated yield to treasury (Owner only)
    /// @param token Token address
    /// @param to Recipient address (typically treasury multisig)
    function withdrawYield(address token, address to) external onlyOwner whenNotPaused nonReentrant {
        uint256 balance = yieldBalance[token];
        if (balance == 0) revert();
        if (to == address(0)) revert InvalidAddress();
        
        yieldBalance[token] = 0;
        SafeTransferLib.safeTransfer(token, to, balance);

        emit YieldWithdrawn(token, to, balance);
    }

    /// @notice Emergency withdraw (owner only)
    function emsWithdraw(address token, address to, uint256 amount) external onlyOwner {
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @notice Set the L2 token address for a given L1 token
    function setTokenMapping(address l1Token, address l2Token) external onlyOwner {
        if (l1Token == address(0) || l2Token == address(0)) revert InvalidAddress();
        tokenMapping[l1Token] = l2Token;
        emit TokenMappingSet(l1Token, l2Token);
    }

    /// @notice Set the L2 vault address
    function setL2Vault(address _l2Vault) external onlyOwner {
        if (_l2Vault == address(0)) revert InvalidAddress();
        address oldVault = l2Vault;
        l2Vault = _l2Vault;
        emit L2VaultSet(oldVault, _l2Vault);
    }

    /// @notice Set maximum slippage tolerance (in basis points)
    function setMaxSlippage(uint64 _maxSlippageBps) external onlyOwner {
        if (_maxSlippageBps > 1000) revert();///Max 10%
        uint64 oldSlippage = maxSlippageBps;
        maxSlippageBps = _maxSlippageBps;
        emit SlippageUpdated(oldSlippage, _maxSlippageBps);
    }

    /// @notice Set minimum deposit amount
    function setMinDepositAmount(uint128 _minDepositAmount) external onlyOwner {
        uint128 oldMin = minDepositAmount;
        minDepositAmount = _minDepositAmount;
        emit MinDepositUpdated(oldMin, _minDepositAmount);
    }

    /// @notice Authorize/deauthorize yield receivers
    function setYieldReceiver(address receiver, bool authorized) external onlyOwner {
        authorizedYieldReceivers[receiver] = authorized;
        emit YieldReceiverAuthorized(receiver, authorized);
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

    event TokenMappingSet(address indexed l1Token, address indexed l2Token);
    event L2VaultSet(address indexed oldVault, address indexed newVault);
    event DepositToL2(address indexed token, address indexed user, uint256 amount, uint256 l2TokenAmount);
    event YieldReceived(address indexed token, uint256 amount);
    event YieldWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event SlippageUpdated(uint64 oldSlippage, uint64 newSlippage);
    event MinDepositUpdated(uint128 oldMin, uint128 newMin);
    event YieldReceiverAuthorized(address indexed receiver, bool authorized);
}

