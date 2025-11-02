// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

/// @title IRelayBridge
/// @notice Interface for Relay.link bridge on Ink L2
/// @dev Docs: https://relay.link/docs
interface IRelayBridge {
    function bridge(
        address token,
        uint256 amount,
        address recipient,
        uint256 destinationChainId
    ) external payable;
    
    function bridgeAndCall(
        address token,
        uint256 amount,
        address target,
        bytes calldata data,
        uint256 destinationChainId
    ) external payable;
    
    function getRelayFee(
        address token,
        uint256 amount,
        uint256 destinationChainId
    ) external view returns (uint256 fee);
}

/// @title IL2CrossDomainMessenger
/// @notice Interface for Optimism L2 Cross Domain Messenger
interface IL2CrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
}

/// @title ITydro //aave v3
interface ITydro {
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

/// @title IVelodrome
interface IVelodrome {
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
    
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
}

/// @title ICurve
interface ICurve {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external returns (uint256);
    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts) external returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256 min_amount) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
}

/// @title IERC20Minimal
interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @title YieldManagerRelay
/// @notice Multi-protocol yield aggregator with L1 control and Relay.link bridging
/// @dev Optimized for Ink L2 with gas-efficient storage patterns
/// @author pepecoin core
contract YieldManagerRelay is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error ZeroAmount();
    error ZeroAddress();
    error InvalidStrategy();
    error InsufficientBalance();
    error BridgeFailed();
    error Paused();
    error OnlyL1Controller();
    error SlippageExceeded();
    error InvalidPair();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Deployed(address indexed token, uint256 amount, uint8 indexed strategy);
    event Harvested(address indexed token, uint256 yield, uint256 bridged, uint256 compounded);
    event Rebalanced(address indexed token, uint256 amount, uint8 from, uint8 to);
    event Bridged(address indexed token, uint256 amount, address indexed recipient);
    event EmergencyWithdrawn(address indexed token, uint256 amount);
    event PauseToggled(bool paused);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CONSTANTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 private constant BPS = 10_000;
    uint256 private constant BRIDGE_BPS = 5_000; // 50% to L1
    uint256 private constant COMPOUND_BPS = 5_000; // 50% compound
    uint256 private constant ETHEREUM_CHAIN_ID = 1;
    uint256 private constant MIN_BRIDGE_AMOUNT = 0.001 ether;
    
    uint8 internal constant STRATEGY_TYDRO = 1;
    uint8 internal constant STRATEGY_VELO = 2;
    uint8 internal constant STRATEGY_CURVE = 3;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   IMMUTABLE STORAGE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address private immutable TYDRO;
    address private immutable VELO;
    address private immutable CURVE;
    address private immutable RELAY_BRIDGE;
    address private immutable L1_RECIPIENT;
    address private immutable L1_CONTROLLER;
    address private immutable L2_MESSENGER;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Packed: paused (1 bit) | lastHarvest (40 bits) | spare (215 bits)
    uint256 private _packedState;
    /// @dev token => strategy => amount
    mapping(address => mapping(uint8 => uint256)) private _positions;
    /// @dev token => aToken address (Tydro)
    mapping(address => address) private _aTokens;
    /// @dev keccak256(tokenA, tokenB) => LP amount
    mapping(bytes32 => uint256) private _veloLP;
    /// @dev keccak256(tokenA, tokenB) => pair address
    mapping(bytes32 => address) private _veloPairs;
    /// @dev token => pool => LP amount (Curve)
    mapping(address => mapping(address => uint256)) private _curveLP;
    
    /// @dev Total yield generated per token
    mapping(address => uint256) public totalYield;
    /// @dev Total amount bridged to L1 per token
    mapping(address => uint256) public totalBridged;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploys a new YieldManager instance
    /// @param tydro Tydro (Aave fork) pool address
    /// @param velo Velodrome router address
    /// @param curve Curve pool address
    /// @param relayBridge Relay.link bridge address on Ink
    /// @param l1Recipient Address to receive bridged funds on L1
    /// @param l1Controller L1 controller address (for cross-chain commands)
    /// @param l2Messenger L2 CrossDomainMessenger address
    constructor(
        address tydro,
        address velo,
        address curve,
        address relayBridge,
        address l1Recipient,
        address l1Controller,
        address l2Messenger
    ) {
        if (tydro == address(0) || velo == address(0) || curve == address(0)) revert ZeroAddress();
        if (relayBridge == address(0) || l1Recipient == address(0)) revert ZeroAddress();
        
        TYDRO = tydro;
        VELO = velo;
        CURVE = curve;
        RELAY_BRIDGE = relayBridge;
        L1_RECIPIENT = l1Recipient;
        L1_CONTROLLER = l1Controller;
        L2_MESSENGER = l2Messenger;
        
        _initializeOwner(msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier whenNotPaused() {
        if (_isPaused()) revert Paused();
        _;
    }

    modifier onlyL1Controller() {
        if (msg.sender != L2_MESSENGER) revert OnlyL1Controller();
        if (IL2CrossDomainMessenger(L2_MESSENGER).xDomainMessageSender() != L1_CONTROLLER) {
            revert OnlyL1Controller();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CORE DEPLOYMENT                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploy funds to a yield strategy
    /// @param token Token to deploy
    /// @param amount Amount to deploy
    /// @param strategy Strategy ID (1=Tydro, 2=Velo, 3=Curve)
    function deployToStrategy(
        address token,
        uint256 amount,
        uint8 strategy
    ) external onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (strategy == 0 || strategy > 3) revert InvalidStrategy();
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        if (strategy == STRATEGY_TYDRO) {
            _deployToTydro(token, amount);
        } else if (strategy == STRATEGY_VELO) {
            revert("use deployToVelodrome for dex");
        } else {
            revert("Use deployToCurve for stable pools");
        }
        
        unchecked {
            _positions[token][strategy] += amount;
        }
        
        emit Deployed(token, amount, strategy);
    }

    /// @notice Deploy funds to Velodrome (requires pair)
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param amountA Amount of tokenA
    /// @param amountB Amount of tokenB
    /// @param stable Whether it's a stable pair
    /// @param minA Minimum tokenA to add
    /// @param minB Minimum tokenB to add
    function deployToVelodrome(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bool stable,
        uint256 minA,
        uint256 minB
    ) external onlyOwner whenNotPaused nonReentrant {
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        tokenA.safeApprove(VELO, amountA);
        tokenB.safeApprove(VELO, amountB);
        
        (uint256 usedA, uint256 usedB, uint256 liquidity) = IVelodrome(VELO).addLiquidity(
            tokenA,
            tokenB,
            stable,
            amountA,
            amountB,
            minA,
            minB,
            address(this),
            block.timestamp
        );
        
        bytes32 pairId = _getPairId(tokenA, tokenB);
        unchecked {
            _veloLP[pairId] += liquidity;
            _positions[tokenA][STRATEGY_VELO] += usedA;
            _positions[tokenB][STRATEGY_VELO] += usedB;
        }
        
        address pair = IVelodrome(VELO).getPair(tokenA, tokenB, stable);
        _veloPairs[pairId] = pair;
        
        if (usedA < amountA) tokenA.safeTransfer(msg.sender, amountA - usedA);
        if (usedB < amountB) tokenB.safeTransfer(msg.sender, amountB - usedB);
        
        emit Deployed(tokenA, usedA, STRATEGY_VELO);
        emit Deployed(tokenB, usedB, STRATEGY_VELO);
    }

    /// @notice Deploy funds to Curve stable pool
    /// @param pool Curve pool address
    /// @param token0 First token
    /// @param token1 Second token
    /// @param amount0 Amount of first token
    /// @param amount1 Amount of second token
    /// @param minMint Minimum LP tokens to receive
    function deployToCurve(
        address pool,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 minMint
    ) external onlyOwner whenNotPaused nonReentrant {
        if (amount0 == 0 && amount1 == 0) revert ZeroAmount();
        if (pool == address(0)) revert ZeroAddress();
        if (amount0 > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0);
            token0.safeApprove(pool, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1);
            token1.safeApprove(pool, amount1);
        }
        
        uint256[2] memory amounts = [amount0, amount1];
        uint256 lpTokens = ICurve(pool).add_liquidity(amounts, minMint);
        unchecked {
            if (amount0 > 0) {
                _curveLP[token0][pool] += lpTokens / 2;
                _positions[token0][STRATEGY_CURVE] += amount0;
            }
            if (amount1 > 0) {
                _curveLP[token1][pool] += lpTokens / 2;
                _positions[token1][STRATEGY_CURVE] += amount1;
            }
        }
        
        if (amount0 > 0) emit Deployed(token0, amount0, STRATEGY_CURVE);
        if (amount1 > 0) emit Deployed(token1, amount1, STRATEGY_CURVE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    YIELD HARVEST                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Harvest yield from Tydro (lending)
    /// @param token Token to harvest
    /// @return yieldAmount Total yield harvested
    function harvestTydro(address token) 
        external 
        onlyOwner 
        whenNotPaused 
        nonReentrant 
        returns (uint256 yieldAmount) 
    {
        uint256 deposited = _positions[token][STRATEGY_TYDRO];
        if (deposited == 0) revert InsufficientBalance();
        
        address aToken = _getAToken(token);
        uint256 currentBalance = IERC20Minimal(aToken).balanceOf(address(this));
        if (currentBalance <= deposited) return 0;
        
        unchecked {
            yieldAmount = currentBalance - deposited;
        }
        ITydro(TYDRO).withdraw(token, yieldAmount, address(this));
        
        _processYield(token, yieldAmount);
        
        emit Harvested(token, yieldAmount, yieldAmount.mulDiv(BRIDGE_BPS, BPS), yieldAmount.mulDiv(COMPOUND_BPS, BPS));
    }

    /// @notice Harvest yield from Velodrome (LP fees)
    /// @param tokenA First token in pair
    /// @param tokenB Second token in pair
    /// @param stable Whether it's a stable pair
    /// @param minA Minimum tokenA to receive
    /// @param minB Minimum tokenB to receive
    function harvestVelodrome(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 minA,
        uint256 minB
    ) external onlyOwner whenNotPaused nonReentrant returns (uint256 yieldA, uint256 yieldB) {
        bytes32 pairId = _getPairId(tokenA, tokenB);
        uint256 liquidity = _veloLP[pairId];
        if (liquidity == 0) revert InsufficientBalance();
        // rm a small portion to realize fees (1%)
        uint256 harvestAmount = liquidity / 100;
        if (harvestAmount == 0) revert ZeroAmount();
        address pair = _veloPairs[pairId];
        if (pair == address(0)) revert InvalidPair();
        
        IERC20Minimal(pair).approve(VELO, harvestAmount);
        
        (uint256 amountA, uint256 amountB) = IVelodrome(VELO).removeLiquidity(
            tokenA,
            tokenB,
            stable,
            harvestAmount,
            minA,
            minB,
            address(this),
            block.timestamp
        );
        
        unchecked {
            _veloLP[pairId] -= harvestAmount;
            yieldA = amountA > _positions[tokenA][STRATEGY_VELO] * harvestAmount / liquidity 
                ? amountA - (_positions[tokenA][STRATEGY_VELO] * harvestAmount / liquidity) 
                : 0;
            yieldB = amountB > _positions[tokenB][STRATEGY_VELO] * harvestAmount / liquidity
                ? amountB - (_positions[tokenB][STRATEGY_VELO] * harvestAmount / liquidity)
                : 0;
        }
        
        if (yieldA > 0) _processYield(tokenA, yieldA);
        if (yieldB > 0) _processYield(tokenB, yieldB);
        
        emit Harvested(tokenA, yieldA, yieldA.mulDiv(BRIDGE_BPS, BPS), yieldA.mulDiv(COMPOUND_BPS, BPS));
        emit Harvested(tokenB, yieldB, yieldB.mulDiv(BRIDGE_BPS, BPS), yieldB.mulDiv(COMPOUND_BPS, BPS));
    }

    /// @notice Harvest from Curve (gauge rewards or pool fees)
    /// @param pool Curve pool address
    /// @param token Token to harvest
    /// @param minAmount Minimum amount to receive
    function harvestCurve(
        address pool,
        address token,
        uint256 minAmount
    ) external onlyOwner whenNotPaused nonReentrant returns (uint256 yieldAmount) {
        uint256 lpAmount = _curveLP[token][pool];
        if (lpAmount == 0) revert InsufficientBalance();
        uint256 harvestAmount = lpAmount / 100;
        if (harvestAmount == 0) revert ZeroAmount();
        
        IERC20Minimal(pool).approve(pool, harvestAmount);
        uint256 received = ICurve(pool).remove_liquidity_one_coin(
            harvestAmount,
            0, ///coin index (adjust per pool)
            minAmount
        );
        unchecked {
            _curveLP[token][pool] -= harvestAmount;
            uint256 principal = _positions[token][STRATEGY_CURVE] * harvestAmount / lpAmount;
            yieldAmount = received > principal ? received - principal : 0;
        }
        
        if (yieldAmount > 0) _processYield(token, yieldAmount);
        
        emit Harvested(token, yieldAmount, yieldAmount.mulDiv(BRIDGE_BPS, BPS), yieldAmount.mulDiv(COMPOUND_BPS, BPS));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   YIELD PROCESSING                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Process harvested yield: 50% bridge to L1, 50% compound
    function _processYield(address token, uint256 amount) private {
        unchecked {
            totalYield[token] += amount;
        }
        
        uint256 toBridge = amount.mulDiv(BRIDGE_BPS, BPS);
        uint256 toCompound = amount - toBridge;
        if (toBridge >= MIN_BRIDGE_AMOUNT) {
            _bridgeToL1(token, toBridge);
        } else {
            ///if too smol, add & compound
            toCompound += toBridge;
        }
        if (toCompound > 0) {
            _deployToTydro(token, toCompound);
            unchecked {
                _positions[token][STRATEGY_TYDRO] += toCompound;
            }
        }
        
        _updateLastHarvest();
    }

    /// @dev Bridge tokens to L1 using Relay.link
    function _bridgeToL1(address token, uint256 amount) private {
        token.safeApprove(RELAY_BRIDGE, amount);
        uint256 fee = IRelayBridge(RELAY_BRIDGE).getRelayFee(token, amount, ETHEREUM_CHAIN_ID);
        ///bridge with phone call to L1 controller
        bytes memory callData = abi.encodeWithSignature(
            "notifyYieldReceived(address,uint256)",
            token,
            amount
        );
        
        IRelayBridge(RELAY_BRIDGE).bridgeAndCall{value: fee}(
            token,
            amount,
            L1_CONTROLLER,
            callData,
            ETHEREUM_CHAIN_ID
        );
        
        unchecked {
            totalBridged[token] += amount;
        }
        
        emit Bridged(token, amount, L1_RECIPIENT);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    REBALANCING                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Rebalance funds between strategies
    /// @param token Token to rebalance
    /// @param amount Amount to move
    /// @param fromStrategy Source strategy
    /// @param toStrategy Destination strategy
    function rebalance(
        address token,
        uint256 amount,
        uint8 fromStrategy,
        uint8 toStrategy
    ) external onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (fromStrategy == 0 || fromStrategy > 3) revert InvalidStrategy();
        if (toStrategy == 0 || toStrategy > 3) revert InvalidStrategy();
        if (fromStrategy == toStrategy) revert InvalidStrategy();
        
        uint256 available = _positions[token][fromStrategy];
        if (available < amount) revert InsufficientBalance();
        
        // Withdraw from source
        if (fromStrategy == STRATEGY_TYDRO) {
            ITydro(TYDRO).withdraw(token, amount, address(this));
        }
        ///todo: more velo/curve logic at some point
        if (toStrategy == STRATEGY_TYDRO) {
            _deployToTydro(token, amount);
        }
        
        unchecked {
            _positions[token][fromStrategy] -= amount;
            _positions[token][toStrategy] += amount;
        }
        
        emit Rebalanced(token, amount, fromStrategy, toStrategy);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 L1 CONTROLLER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Harvest from L1 controller (via CrossDomainMessenger)
    /// @param token Token to harvest
    /// @param strategy Strategy to harvest from
    function harvestFromL1(address token, uint8 strategy) 
        external 
        onlyL1Controller 
        nonReentrant 
    {
        if (strategy == STRATEGY_TYDRO) {
            this.harvestTydro(token);
        }
        ///todo: more velo/curve logic at some point
    }

    /// @notice Batch harvest multiple strategies from L1
    /// @param tokens Tokens to harvest
    /// @param strategies Corresponding strategies
    function batchHarvestFromL1(
        address[] calldata tokens,
        uint8[] calldata strategies
    ) external onlyL1Controller nonReentrant {
        uint256 length = tokens.length;
        if (length != strategies.length) revert InvalidStrategy();
        
        for (uint256 i; i < length;) {
            if (strategies[i] == STRATEGY_TYDRO) {
                this.harvestTydro(tokens[i]);
            }
            unchecked { ++i; }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   INTERNAL HELPERS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deployToTydro(address token, uint256 amount) private {
        token.safeApprove(TYDRO, amount);
        ITydro(TYDRO).supply(token, amount, address(this), 0);
        //cache aTokens
        if (_aTokens[token] == address(0)) {
            (, , , , , , , , address aToken, , , , , , ) = ITydro(TYDRO).getReserveData(token);
            _aTokens[token] = aToken;
        }
    }

    function _getAToken(address token) private view returns (address) {
        address cached = _aTokens[token];
        if (cached != address(0)) return cached;
        
        (, , , , , , , , address aToken, , , , , , ) = ITydro(TYDRO).getReserveData(token);
        return aToken;
    }

    function _getPairId(address tokenA, address tokenB) private pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    function _isPaused() private view returns (bool) {
        return _packedState & 1 == 1;
    }

    function _updateLastHarvest() private {
        _packedState = (_packedState & ~uint256(0xFFFFFFFFFF << 1)) | (block.timestamp << 1);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ADMIN FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function waitPause() external onlyOwner {
        _packedState ^= 1;
        emit PauseToggled(_isPaused());
    }

    function emsWithdraw(address token, uint256 amount) 
        external 
        onlyOwner 
    {
        token.safeTransfer(msg.sender, amount);
        emit EmergencyWithdrawn(token, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getPosition(address token, uint8 strategy) external view returns (uint256) {
        return _positions[token][strategy];
    }

    function getVeloLP(address tokenA, address tokenB) external view returns (uint256) {
        return _veloLP[_getPairId(tokenA, tokenB)];
    }

    function getCurveLP(address token, address pool) external view returns (uint256) {
        return _curveLP[token][pool];
    }

    function isPaused() external view returns (bool) {
        return _isPaused();
    }

    function getLastHarvest() external view returns (uint256) {
        return (_packedState >> 1) & 0xFFFFFFFFFF;
    }

    /// @notice Required for receiving ETH (Relay fees)
    receive() external payable {}
}
