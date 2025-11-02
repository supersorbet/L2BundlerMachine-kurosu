// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldManagerDualBridge
 * @notice Manages yield across Tydro and Velodrome with DUAL bridge support
 * @dev Supports both Across Protocol (fast) AND native L2StandardBridge (fallback)
 */
contract YieldManagerDualBridge is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Across Protocol SpokePool (Fast Bridge - 2 seconds)
     * @dev Intent-based bridge with competitive relayers
     */
    interface IAcrossSpokePool {
        function depositV3(
            address depositor,
            address recipient,
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            uint256 destinationChainId,
            address exclusiveRelayer,
            uint32 quoteTimestamp,
            uint32 fillDeadline,
            uint32 exclusivityDeadline,
            bytes calldata message
        ) external payable;
    }

    /**
     * @notice L2StandardBridge (Native Bridge - 7 days)
     * @dev Standard OP Stack bridge with fraud proofs
     */
    interface IL2StandardBridge {
        function withdrawTo(
            address _l2Token,
            address _to,
            uint256 _amount,
            uint32 _minGasLimit,
            bytes calldata _extraData
        ) external;
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///PROTOCOL INTERFACES
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    interface IPool {
        function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
        function withdraw(address asset, uint256 amount, address to) external returns (uint256);
        function getReserveData(address asset) external view returns (
            uint256, uint128, uint128, uint128, uint128, uint128, uint40, uint16,
            address aTokenAddress,
            address, address, address, uint128, uint128, uint128
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
            address tokenA, address tokenB, bool stable,
            uint256 amountADesired, uint256 amountBDesired,
            uint256 amountAMin, uint256 amountBMin,
            address to, uint256 deadline
        ) external returns (uint256, uint256, uint256);

        function removeLiquidity(
            address tokenA, address tokenB, bool stable,
            uint256 liquidity, uint256 amountAMin, uint256 amountBMin,
            address to, uint256 deadline
        ) external returns (uint256, uint256);

        function pairFor(address tokenA, address tokenB, bool stable) external view returns (address);
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///BRIDGE TYPE ENUM
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    enum BridgeType {
        ACROSS,   ///Fast bridge (2 seconds, ~$0.05 fee)
        NATIVE    ///Native bridge (7 days, minimal fee)
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///STATE VARIABLES
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

   ///Bridge addresses
    address public immutable ACROSS_SPOKE_POOL;     ///Across Protocol on Ink L2
    address public immutable L2_STANDARD_BRIDGE;    ///Native bridge on Ink L2
    
   ///Bridge configuration
    address public l1Recipient;                      ///L1 recipient address
    BridgeType public defaultBridge;                 ///Default bridge to use
    uint32 public nativeBridgeGasLimit;             ///Gas limit for native bridge
    uint256 public acrossSlippageBps;               ///Slippage tolerance for Across (basis points)
    
   ///Protocol addresses
    address public immutable TYDRO_POOL;
    address public immutable VELO_ROUTER;

   ///Position tracking
    struct Position {
        uint256 principal;
        uint256 lastHarvest;
    }

    mapping(address => mapping(uint256 => Position)) private _positions;
    mapping(address => address) private _aTokens;
    mapping(bytes32 => uint256) private _veloLP;
    mapping(bytes32 => address) private _veloPairs;

   ///Bridge usage tracking
    mapping(BridgeType => uint256) public bridgeUsageCount;
    mapping(BridgeType => uint256) public totalBridgedAmount;

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///EVENTS
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    event Deployed(uint256 indexed strategyId, address indexed token, uint256 amount);
    event Harvested(uint256 indexed strategyId, address indexed token, uint256 yieldAmount);
    event BridgedToL1(
        address indexed token,
        uint256 amount,
        address indexed l1Recipient,
        BridgeType bridgeType
    );
    event Withdrawn(uint256 indexed strategyId, address indexed token, uint256 amount);
    event BridgeConfigUpdated(BridgeType newDefault, uint256 slippageBps, uint32 gasLimit);
    event L1RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///CONSTRUCTOR
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    constructor(
        address _acrossSpokePool,
        address _l2StandardBridge,
        address _tydroPool,
        address _veloRouter,
        address _l1Recipient
    ) Ownable(msg.sender) {
        require(_acrossSpokePool != address(0), "Invalid Across pool");
        require(_l2StandardBridge != address(0), "Invalid native bridge");
        require(_tydroPool != address(0), "Invalid Tydro pool");
        require(_veloRouter != address(0), "Invalid Velo router");
        require(_l1Recipient != address(0), "Invalid L1 recipient");

        ACROSS_SPOKE_POOL = _acrossSpokePool;
        L2_STANDARD_BRIDGE = _l2StandardBridge;
        TYDRO_POOL = _tydroPool;
        VELO_ROUTER = _veloRouter;
        l1Recipient = _l1Recipient;
        
       ///Default configuration
        defaultBridge = BridgeType.ACROSS;          ///Use Across by default (faster)
        nativeBridgeGasLimit = 200000;              ///200k gas for native bridge
        acrossSlippageBps = 10;                     ///0.1% slippage tolerance
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///BRIDGE CONFIGURATION
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    function setL1Recipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid recipient");
        address oldRecipient = l1Recipient;
        l1Recipient = _newRecipient;
        emit L1RecipientUpdated(oldRecipient, _newRecipient);
    }

    function setBridgeConfig(
        BridgeType _defaultBridge,
        uint256 _slippageBps,
        uint32 _gasLimit
    ) external onlyOwner {
        require(_slippageBps <= 100, "Slippage too high");///Max 1%
        require(_gasLimit >= 100000, "Gas limit too low");
        
        defaultBridge = _defaultBridge;
        acrossSlippageBps = _slippageBps;
        nativeBridgeGasLimit = _gasLimit;
        
        emit BridgeConfigUpdated(_defaultBridge, _slippageBps, _gasLimit);
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///DUAL BRIDGE IMPLEMENTATION
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    /**
     * @notice Bridge tokens to L1 using specified bridge type
     * @param token Token to bridge
     * @param amount Amount to bridge
     * @param bridgeType Which bridge to use (ACROSS or NATIVE)
     */
    function _bridgeToL1(
        address token,
        uint256 amount,
        BridgeType bridgeType
    ) internal {
        require(amount > 0, "Nothing to bridge");
        
        if (bridgeType == BridgeType.ACROSS) {
            _bridgeViaAcross(token, amount);
        } else {
            _bridgeViaNative(token, amount);
        }
        
       ///Track usage
        bridgeUsageCount[bridgeType]++;
        totalBridgedAmount[bridgeType] += amount;
        
        emit BridgedToL1(token, amount, l1Recipient, bridgeType);
    }

    /**
     * @notice Bridge via Across Protocol (Fast - 2 seconds)
     * @dev Uses intent-based relayers for instant fills
     */
    function _bridgeViaAcross(address token, uint256 amount) internal {
       ///Calculate output amount with slippage
        uint256 outputAmount = amount * (10000 - acrossSlippageBps) / 10000;
        
       ///Approve Across SpokePool
        IERC20(token).safeIncreaseAllowance(ACROSS_SPOKE_POOL, amount);
        
       ///Bridge via Across Protocol
        IAcrossSpokePool(ACROSS_SPOKE_POOL).depositV3(
            address(this),                         ///depositor
            l1Recipient,                           ///recipient on L1
            token,                                 ///input token (on L2)
            token,                                 ///output token (on L1)
            amount,                                ///input amount
            outputAmount,                          ///output amount (with slippage)
            1,                                     ///destination chain ID (Ethereum = 1)
            address(0),                            ///no exclusive relayer
            uint32(block.timestamp),               ///quote timestamp
            uint32(block.timestamp + 1 hours),     ///fill deadline
            0,                                     ///no exclusivity deadline
            ""                                     ///no message
        );
    }

    /**
     * @notice Bridge via native L2StandardBridge (Slow - 7 days)
     * @dev Standard OP Stack bridge with fraud proof period
     */
    function _bridgeViaNative(address token, uint256 amount) internal {
       ///Approve native bridge
        IERC20(token).safeIncreaseAllowance(L2_STANDARD_BRIDGE, amount);
        
       ///Bridge via native L2StandardBridge
        IL2StandardBridge(L2_STANDARD_BRIDGE).withdrawTo(
            token,                 ///L2 token address
            l1Recipient,           ///recipient on L1
            amount,                ///amount to bridge
            nativeBridgeGasLimit,  ///gas limit for L1 execution
            ""                     ///extra data
        );
    }

    /**
     * @notice Bridge using default bridge type
     */
    function _bridgeToL1Default(address token, uint256 amount) internal {
        _bridgeToL1(token, amount, defaultBridge);
    }

    /**
     * @notice Try Across first, fallback to native if it fails
     * @dev Provides maximum reliability
     */
    function _bridgeToL1WithFallback(address token, uint256 amount) internal {
        try this.externalBridgeViaAcross(token, amount) {
           ///Across succeeded
            bridgeUsageCount[BridgeType.ACROSS]++;
            totalBridgedAmount[BridgeType.ACROSS] += amount;
            emit BridgedToL1(token, amount, l1Recipient, BridgeType.ACROSS);
        } catch {
           ///Across failed, use native bridge
            _bridgeViaNative(token, amount);
            bridgeUsageCount[BridgeType.NATIVE]++;
            totalBridgedAmount[BridgeType.NATIVE] += amount;
            emit BridgedToL1(token, amount, l1Recipient, BridgeType.NATIVE);
        }
    }

    /**
     * @notice External function for try/catch pattern
     */
    function externalBridgeViaAcross(address token, uint256 amount) external {
        require(msg.sender == address(this), "Only self");
        _bridgeViaAcross(token, amount);
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///TYDRO (AAVE V3 FORK) INTEGRATION
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

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

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///VELODROME INTEGRATION
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

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
            amountA, amountB, 0, 0,
            address(this), block.timestamp
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
            
            (uint256 fee0,) = IVeloPair(pair).claimFees();
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
        return _veloLP[_pairHash(tokenA, tokenB, stable)];
    }

    function getVeloClaimableFees(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256, uint256) {
        address pair = _veloPairs[_pairHash(tokenA, tokenB, stable)];
        if (pair == address(0)) return (0, 0);
        return (IVeloPair(pair).claimableFeesToken0(), IVeloPair(pair).claimableFeesToken1());
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///UNIFIED HARVEST WITH BRIDGE SELECTION
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    /**
     * @notice Harvest yield using default bridge
     */
    function harvest(
        uint256 strategyId,
        address token,
        bytes calldata auxData
    ) external onlyOwner {
        _harvestWithBridge(strategyId, token, auxData, defaultBridge);
    }

    /**
     * @notice Harvest yield with specific bridge type
     */
    function harvestWithBridge(
        uint256 strategyId,
        address token,
        bytes calldata auxData,
        BridgeType bridgeType
    ) external onlyOwner {
        _harvestWithBridge(strategyId, token, auxData, bridgeType);
    }

    /**
     * @notice Harvest yield with automatic fallback
     */
    function harvestWithFallback(
        uint256 strategyId,
        address token,
        bytes calldata auxData
    ) external onlyOwner {
        uint256 yieldAmount = _getYieldAmount(strategyId, token, auxData);
        require(yieldAmount > 0, "No yield");
        
       ///Split 50/50
        uint256 bridgeAmount = yieldAmount / 2;
        uint256 compoundAmount = yieldAmount - bridgeAmount;
        
       ///Bridge with fallback
        _bridgeToL1WithFallback(token, bridgeAmount);
        
       ///Compound
        _compoundYield(strategyId, token, compoundAmount);
        
        emit Harvested(strategyId, token, yieldAmount);
    }

    /**
     * @notice Internal harvest implementation
     */
    function _harvestWithBridge(
        uint256 strategyId,
        address token,
        bytes calldata auxData,
        BridgeType bridgeType
    ) internal {
        uint256 yieldAmount = _getYieldAmount(strategyId, token, auxData);
        require(yieldAmount > 0, "No yield");
        
       ///Split 50/50
        uint256 bridgeAmount = yieldAmount / 2;
        uint256 compoundAmount = yieldAmount - bridgeAmount;
        
       ///Bridge using specified type
        _bridgeToL1(token, bridgeAmount, bridgeType);
        
       ///Compound
        _compoundYield(strategyId, token, compoundAmount);
        
        emit Harvested(strategyId, token, yieldAmount);
    }

    function _getYieldAmount(
        uint256 strategyId,
        address token,
        bytes calldata auxData
    ) internal returns (uint256) {
        if (strategyId == 1) {
            return _harvestTydro(token);
        } else if (strategyId == 2) {
            address tokenB = abi.decode(auxData, (address));
            return _harvestVelo(token, tokenB);
        } else {
            revert("Invalid strategy");
        }
    }

    function _compoundYield(
        uint256 strategyId,
        address token,
        uint256 amount
    ) internal {
        if (strategyId == 1) {
            IERC20(token).safeIncreaseAllowance(TYDRO_POOL, amount);
            IPool(TYDRO_POOL).supply(token, amount, address(this), 0);
            _positions[token][1].principal += amount;
        }
       ///Note: Velodrome compounding would require re-adding liquidity
    }

    /**
     * @notice Batch harvest with mixed bridge types
     */
    function batchHarvest(
        uint256[] calldata strategyIds,
        address[] calldata tokens,
        bytes[] calldata auxData,
        BridgeType[] calldata bridgeTypes
    ) external onlyOwner {
        require(strategyIds.length == tokens.length, "Length mismatch");
        require(tokens.length == auxData.length, "Length mismatch");
        require(auxData.length == bridgeTypes.length, "Length mismatch");
        
        for (uint256 i = 0; i < strategyIds.length; i++) {
            uint256 yieldAmount = _getYieldAmount(strategyIds[i], tokens[i], auxData[i]);
            
            if (yieldAmount > 0) {
                uint256 bridgeAmount = yieldAmount / 2;
                uint256 compoundAmount = yieldAmount - bridgeAmount;
                
                _bridgeToL1(tokens[i], bridgeAmount, bridgeTypes[i]);
                _compoundYield(strategyIds[i], tokens[i], compoundAmount);
                
                emit Harvested(strategyIds[i], tokens[i], yieldAmount);
            }
        }
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///BRIDGE STATISTICS
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    function getBridgeStats(BridgeType bridgeType) external view returns (
        uint256 usageCount,
        uint256 totalAmount
    ) {
        return (bridgeUsageCount[bridgeType], totalBridgedAmount[bridgeType]);
    }

   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄
   ///EMERGENCY FUNCTIONS
   ///❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄❄

    function withdrawFromTydro(address token, uint256 amount) external onlyOwner {
        uint256 withdrawn = IPool(TYDRO_POOL).withdraw(token, amount, msg.sender);
        _positions[token][1].principal -= amount;
        emit Withdrawn(1, token, withdrawn);
    }

    function withdrawFromVelo(
        address tokenA, address tokenB, bool stable, uint256 liquidity
    ) external onlyOwner {
        bytes32 pairHash = _pairHash(tokenA, tokenB, stable);
        address pair = _veloPairs[pairHash];
        require(pair != address(0), "Pair not found");
        
        IERC20(pair).safeIncreaseAllowance(VELO_ROUTER, liquidity);
        IVeloRouter(VELO_ROUTER).removeLiquidity(
            tokenA, tokenB, stable, liquidity, 0, 0, msg.sender, block.timestamp
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
