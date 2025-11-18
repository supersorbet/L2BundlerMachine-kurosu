// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockAcrossBridge
/// @notice Mock Across bridge for testing cross-chain operations
contract MockAcrossBridge {
    using SafeTransferLib for address;

    /// @dev Bridge fee (basis points)
    uint256 public constant BRIDGE_FEE_BPS = 10; // 0.1%
    
    /// @dev Track deposits
    struct Deposit {
        address recipient;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint256 destinationChainId;
        bool filled;
    }
    
    mapping(bytes32 => Deposit) public deposits;
    mapping(address => mapping(address => uint256)) public balances; // recipient => token => amount
    
    event DepositCreated(bytes32 indexed depositId, address indexed recipient, address token, uint256 amount);
    event DepositFilled(bytes32 indexed depositId);
    
    /// @notice Simulate deposit on origin chain
    function deposit(
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address,
        uint256,
        bytes calldata
    ) external {
        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);
        
        bytes32 depositId = keccak256(abi.encodePacked(
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            block.timestamp,
            block.number
        ));
        
        deposits[depositId] = Deposit({
            recipient: recipient,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            destinationChainId: destinationChainId,
            filled: false
        });
        
        emit DepositCreated(depositId, recipient, outputToken, outputAmount);
    }
    
    /// @notice Fill deposit (simulates relayer filling on destination)
    function fillDeposit(bytes32 depositId) external {
        Deposit storage dep = deposits[depositId];
        require(!dep.filled, "Already filled");
        
        // Calculate amount after fee
        uint256 bridgeFee = (dep.outputAmount * BRIDGE_FEE_BPS) / 10000;
        uint256 amountOut = dep.outputAmount - bridgeFee;
        
        // Transfer to recipient
        dep.outputToken.safeTransfer(dep.recipient, amountOut);
        dep.filled = true;
        
        emit DepositFilled(depositId);
    }

    /// @notice depositNow mock to match ISpokePool.depositNow signature used by vault
    function depositNow(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 /*destinationChainId*/,
        uint64 /*relayerFeePct*/,
        uint32 /*quoteTimestamp*/,
        bytes calldata /*message*/,
        uint256 /*maxCount*/
    ) external {
        // Pull tokens from depositor
        inputToken.safeTransferFrom(depositor, address(this), inputAmount);
        
        bytes32 depositId = keccak256(abi.encodePacked(
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            block.timestamp,
            block.number
        ));
        deposits[depositId] = Deposit({
            recipient: recipient,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            destinationChainId: 0,
            filled: false
        });
        emit DepositCreated(depositId, recipient, outputToken, outputAmount);
    }
    
    /// @notice Get deposit info
    function getDeposit(bytes32 depositId) external view returns (Deposit memory) {
        return deposits[depositId];
    }
}

/// @title MockRelayDepository
/// @notice Mock Relay Protocol depository for testing
contract MockRelayDepository {
    using SafeTransferLib for address;
    
    /// @dev Track deposits
    struct RelayDeposit {
        address recipient;
        address token;
        uint256 amount;
        uint256 destinationChainId;
        uint256 maxFee;
        bool filled;
    }
    
    mapping(bytes32 => RelayDeposit) public deposits;
    
    event DepositInitiated(bytes32 indexed depositId, address indexed recipient, address token, uint256 amount);
    event DepositFilled(bytes32 indexed depositId);
    
    /// @notice Create deposit
    function deposit(
        uint256 destinationChainId,
        address recipient,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint256 deadline
    ) external returns (bytes32 depositId) {
        require(block.timestamp <= deadline, "Deadline passed");
        require(amount > 0, "Zero amount");
        
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        depositId = keccak256(abi.encodePacked(
            recipient,
            token,
            amount,
            destinationChainId,
            block.timestamp,
            block.number
        ));
        
        deposits[depositId] = RelayDeposit({
            recipient: recipient,
            token: token,
            amount: amount,
            destinationChainId: destinationChainId,
            maxFee: maxFee,
            filled: false
        });
        
        emit DepositInitiated(depositId, recipient, token, amount);
    }
    
    /// @notice Fill deposit (simulates relayer)
    function fillDeposit(bytes32 depositId) external {
        RelayDeposit storage dep = deposits[depositId];
        require(!dep.filled, "Already filled");
        
        // Bridge fee (0.1%)
        uint256 fee = dep.amount / 1000;
        uint256 amountOut = dep.amount - fee;
        
        dep.token.safeTransfer(dep.recipient, amountOut);
        dep.filled = true;
        
        emit DepositFilled(depositId);
    }
}

