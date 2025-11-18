// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldManagerWithBridge
 * @notice Manages yield across Tydro and Velodrome, with native bridge integration
 * @dev Uses Ink L2's native Standard Bridge (Optimism fork) for L1 transfers
 */
contract YieldManagerWithBridge is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Standard Bridge interface (Optimism/Base/Ink L2s)
     * @dev This is the L2StandardBridge that exists on all OP Stack chains
     */
    interface IL2StandardBridge {
        /**
         * @notice Withdraws tokens to L1
         * @param _l2Token Address of token on L2
         * @param _amount Amount to bridge
         * @param _minGasLimit Minimum gas limit for L1 execution
         * @param _extraData Extra data for the bridge
         */
        function withdrawTo(
            address _l2Token,
            address _to,
            uint256 _amount,
            uint32 _minGasLimit,
            bytes calldata _extraData
        ) external;
    }


    interface IPool {
        function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
        function withdraw(address asset, uint256 amount, address to) external returns (uint256);
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

    interface IAToken {
        function balanceOf(address account) external view returns (uint256);
    }

    interface IVeloPair {
        function claimFees() external returns (uint256, uint256);
        function claimableFeesToken0() external view returns (uint256);
        function claimableFeesToken1() external view returns (uint256);
    }

    interface IVeloRouter {
        function addLiquidity(
            address tokenA,
            address tokenB,
            bool stable,
            uint256 amountADesired,
            uint256 amountBDesired,
            uint256 amountAMin,
            uint256 amountBMin,
            address to,
            uint256 deadline
        ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

        function removeLiquidity(
            address tokenA,
            address tokenB,
            bool stable,
            uint256 liquidity,
            uint256 amountAMin,
            uint256 amountBMin,
            address to,
            uint256 deadline
        ) external returns (uint256 amountA, uint256 amountB);

        function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);
    }

    address public immutable L2_STANDARD_BRIDGE;
    address public l1Recipient; 
    uint32 public bridgeGasLimit; 
    address public immutable TYDRO_POOL;
    address public immutable VELO_ROUTER;

    // Strategy tracking (1 = Tydro, 2 = Velodrome)
    struct Position {
        uint256 principal;
        uint256 lastHarvest;
    }

    mapping(address => mapping(uint256 => Position)) private _positions; // token => strategy => position
    mapping(address => address) private _aTokens; // token => aToken
    mapping(bytes32 => uint256) private _veloLP; // pairHash => LP amount
    mapping(bytes32 => address) private _veloPairs; // pairHash => pair address

    event Deployed(uint256 indexed strategyId, address indexed token, uint256 amount);
    event Harvested(uint256 indexed strategyId, address indexed token, uint256 yieldAmount);
    event BridgedToL1(address indexed token, uint256 amount, address indexed l1Recipient);
    event Withdrawn(uint256 indexed strategyId, address indexed token, uint256 amount);
    event L1RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Initialize the yield manager
     * @param _l2Bridge Address of L2StandardBridge on Ink
     * @param _tydroPool Address of Tydro lending pool
     * @param _veloRouter Address of Velodrome router
     * @param _l1Recipient Initial L1 recipient address
     */
    constructor(
        address _l2Bridge,
        address _tydroPool,
        address _veloRouter,
        address _l1Recipient
    ) Ownable(msg.sender) {
        require(_l2Bridge != address(0), "Invalid bridge");
        require(_tydroPool != address(0), "Invalid Tydro pool");
        require(_veloRouter != address(0), "Invalid Velo router");
        require(_l1Recipient != address(0), "Invalid L1 recipient");

        L2_STANDARD_BRIDGE = _l2Bridge;
        TYDRO_POOL = _tydroPool;
        VELO_ROUTER = _veloRouter;
        l1Recipient = _l1Recipient;
        bridgeGasLimit = 200000; // Default 200k gas for L1 execution
    }

    /**
     * @notice Update L1 recipient address
     * @param _newRecipient New L1 recipient
     */
    function setL1Recipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid recipient");
        address oldRecipient = l1Recipient;
        l1Recipient = _newRecipient;
        emit L1RecipientUpdated(oldRecipient, _newRecipient);
    }

    /**
     * @notice Update bridge gas limit
     * @param _gasLimit New gas limit
     */
    function setBridgeGasLimit(uint32 _gasLimit) external onlyOwner {
        require(_gasLimit >= 100000, "Gas limit too low");
        bridgeGasLimit = _gasLimit;
    }

    /**
     * @notice Bridge tokens to L1 using Ink's native bridge
     * @param token Token to bridge
     * @param amount Amount to bridge
     */
    function _bridgeToL1(address token, uint256 amount) internal {
        require(amount > 0, "Nothing to bridge");
        
        // Approve bridge to spend tokens
        IERC20(token).safeIncreaseAllowance(L2_STANDARD_BRIDGE, amount);
        
        // Bridge to L1 using Standard Bridge
        IL2StandardBridge(L2_STANDARD_BRIDGE).withdrawTo(
            token,              // L2 token address
            l1Recipient,        // Recipient on L1
            amount,             // Amount to bridge
            bridgeGasLimit,     // Gas limit for L1 execution
            ""                  // Extra data (empty for simple transfers)
        );
        
        emit BridgedToL1(token, amount, l1Recipient);
    }

    function deployToTydro(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid amount");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeIncreaseAllowance(TYDRO_POOL, amount);
        
        IPool(TYDRO_POOL).supply(token, amount, address(this), 0);
        
        if (_aTokens[token] == address(0)) {
            _aTokens[token] = _getATokenAddress(token);
        }
        
        _positions[token][1].principal += amount;
        _positions[token][1].lastHarvest = block.timestamp;
        
        emit Deployed(1, token, amount);
    }

    function _harvestTydro(address token) internal returns (uint256) {
        address aToken = _aTokens[token];
        require(aToken != address(0), "Not deployed to Tydro");
        
        uint256 aTokenBalance = IAToken(aToken).balanceOf(address(this));
        uint256 principal = _positions[token][1].principal;
        
        if (aTokenBalance <= principal) return 0;
        
        uint256 yieldAmount = aTokenBalance - principal;
        IPool(TYDRO_POOL).withdraw(token, yieldAmount, address(this));
        
        _positions[token][1].lastHarvest = block.timestamp;
        
        return yieldAmount;
    }

    function _getATokenAddress(address asset) internal view returns (address) {
        (,,,,,,,, address aTokenAddress,,,,,,) = IPool(TYDRO_POOL).getReserveData(asset);
        return aTokenAddress;
    }

    function getTydroBalance(address token) external view returns (uint256) {
        address aToken = _aTokens[token];
        if (aToken == address(0)) return 0;
        return IAToken(aToken).balanceOf(address(this));
    }

    function getTydroYield(address token) external view returns (uint256) {
        address aToken = _aTokens[token];
        if (aToken == address(0)) return 0;
        
        uint256 balance = IAToken(aToken).balanceOf(address(this));
        uint256 principal = _positions[token][1].principal;
        
        return balance > principal ? balance - principal : 0;
    }

    function deployToVelo(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable
    ) external onlyOwner {
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);
        
        IERC20(tokenA).safeIncreaseAllowance(VELO_ROUTER, amountA);
        IERC20(tokenB).safeIncreaseAllowance(VELO_ROUTER, amountB);
        
        (,, uint256 liquidity) = IVeloRouter(VELO_ROUTER).addLiquidity(
            tokenA, tokenB, stable,
            amountA, amountB,
            0, 0,
            address(this),
            block.timestamp
        );
        
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = IVeloRouter(VELO_ROUTER).pairFor(tokenA, tokenB, stable);
        
        _veloLP[pairHash] += liquidity;
        _veloPairs[pairHash] = pair;
        _positions[tokenA][2].principal += amountA;
        _positions[tokenA][2].lastHarvest = block.timestamp;
        
        emit Deployed(2, tokenA, amountA);
    }

    function _harvestVelo(address tokenA, address tokenB) internal returns (uint256) {
        uint256 totalFees;
        
        for (uint256 i = 0; i < 2; i++) {
            bool stable = (i == 1);
            bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
            address pair = _veloPairs[pairHash];
            
            if (pair == address(0)) continue;
            
            (uint256 fee0, uint256 fee1) = IVeloPair(pair).claimFees();
            totalFees += fee0;
        }
        
        if (totalFees > 0) {
            _positions[tokenA][2].lastHarvest = block.timestamp;
        }
        
        return totalFees;
    }

    function _pairHash(address tokenA, address tokenB, bool stable) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB, stable));
    }

    function getVeloBalance(address tokenA, address tokenB, bool stable) external view returns (uint256) {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        return _veloLP[pairHash];
    }

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

    /**
     * @notice Harvest yield from strategy and auto-split 50/50
     * @param strategyId 1 = Tydro, 2 = Velodrome
     * @param token Primary token
     * @param auxData For Velodrome: abi.encode(tokenB)
     */
    function harvest(
        uint256 strategyId,
        address token,
        bytes calldata auxData
    ) external onlyOwner {
        uint256 yieldAmount;
        
        if (strategyId == 1) {
            // Tydro
            yieldAmount = _harvestTydro(token);
        } else if (strategyId == 2) {
            // Velodrome
            address tokenB = abi.decode(auxData, (address));
            yieldAmount = _harvestVelo(token, tokenB);
        } else {
            revert("Invalid strategy");
        }
        
        require(yieldAmount > 0, "No yield");
        
        // Split 50/50
        uint256 bridgeAmount = yieldAmount / 2;
        uint256 compoundAmount = yieldAmount - bridgeAmount;
        
        // 1. Bridge 50% to L1
        _bridgeToL1(token, bridgeAmount);
        
        // 2. Re-deploy 50% to same strategy
        if (strategyId == 1) {
            IERC20(token).safeIncreaseAllowance(TYDRO_POOL, compoundAmount);
            IPool(TYDRO_POOL).supply(token, compoundAmount, address(this), 0);
            _positions[token][1].principal += compoundAmount;
        }
        // Note: Velodrome compounding would require re-adding liquidity
        
        emit Harvested(strategyId, token, yieldAmount);
    }

    /**
     * @notice Batch harvest multiple strategies
     * @param strategyIds Array of strategy IDs
     * @param tokens Array of primary tokens
     * @param auxData Array of auxiliary data
     */
    function batchHarvest(
        uint256[] calldata strategyIds,
        address[] calldata tokens,
        bytes[] calldata auxData
    ) external onlyOwner {
        require(strategyIds.length == tokens.length, "Length mismatch");
        require(tokens.length == auxData.length, "Length mismatch");
        
        for (uint256 i = 0; i < strategyIds.length; i++) {
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
                    IERC20(tokens[i]).safeIncreaseAllowance(TYDRO_POOL, compoundAmount);
                    IPool(TYDRO_POOL).supply(tokens[i], compoundAmount, address(this), 0);
                    _positions[tokens[i]][1].principal += compoundAmount;
                }
                
                emit Harvested(strategyIds[i], tokens[i], yieldAmount);
            }
        }
    }

    function withdrawFromTydro(address token, uint256 amount) external onlyOwner {
        uint256 withdrawn = IPool(TYDRO_POOL).withdraw(token, amount, msg.sender);
        _positions[token][1].principal -= amount;
        emit Withdrawn(1, token, withdrawn);
    }

    function withdrawFromVelo(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external onlyOwner {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = _veloPairs[pairHash];
        require(pair != address(0), "Pair not found");
        
        IERC20(pair).safeIncreaseAllowance(VELO_ROUTER, liquidity);
        
        IVeloRouter(VELO_ROUTER).removeLiquidity(
            tokenA, tokenB, stable,
            liquidity,
            0, 0,
            msg.sender,
            block.timestamp
        );
        
        _veloLP[pairHash] -= liquidity;
        emit Withdrawn(2, tokenA, liquidity);
    }

    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
        }
    }
}
