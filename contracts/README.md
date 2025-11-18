# Core Contracts

## 📋 Contract Index

1. [L1DepositorV2\_](./#l1depositorv2_production) - Ethereum L1 contract
2. [BundledYieldVaultV2\_](./#bundledyieldvaultv2_production) - Ink L2 vault
3. [YieldVaultFactory](./#yieldvaultfactory) - Vault deployment factory
4. [YieldAllocator](./#yieldallocator) - Smart extensible strategy allocation

***

## L1DepositorV2\_

**Network**: Ethereum Mainnet\
**Purpose**: Entry point for deposits and yield management on L1

### Overview

The L1Depositor contract serves as the primary interface for users to deposit assets and receive yield. It handles cross-chain bridging via Across Protocol(Full optional Relay.link in future) and maintains yield balances for withdrawal.

### Key Features

* ✅ Owner/User-only deposit operations
* ✅ Cross-chain bridging via Across Protocol/Relay.link
* ✅ Token mapping (L1 → L2)
* ✅ Yield balance tracking
* ✅ Emergency pause functionality
* ✅ Slippage protection

### Contract Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IHubPool} from "./interfaces/IAcross.sol";

contract L1DepositorV2_ is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    address public immutable HUB_POOL;
    uint256 public immutable DESTINATION_CHAIN_ID;
    
    address public l2Vault;
    mapping(address => address) public tokenMapping;
    mapping(address => uint256) public yieldBalance;
    
    uint64 public maxSlippageBps = 75;/// 0.75% default
    uint128 public minDepositAmount = 100;
}
```

### Core Functions

#### `depositToL2`

Deposits tokens to L2 via Across Bridge.

```solidity
function depositToL2(
    address token,
    uint256 amount,
    uint256 minAmount
) external onlyOwner whenNotPaused nonReentrant
```

**Parameters**:

* `token`: L1 token address (e.g., USDT)
* `amount`: Amount to deposit
* `minAmount`: Minimum amount expected on L2 (slippage protection)

**Flow**:

1. Validates token mapping exists
2. Checks minimum deposit amount
3. Validates slippage tolerance
4. Transfers tokens from owner
5. Approves Across HubPool
6. Initiates bridge deposit
7. Updates total deposits tracking

**Example**:

```solidity
// Deposit 10,000 USDT to L2
depositor.depositToL2(
    0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
    10_000_000_000,  // 10,000 USDT (6 decimals)
    9_925_000_000    // Min 9,925 USDT (0.75% slippage)
);
```

#### `setTokenMapping`

Maps L1 token to L2 token address.

```solidity
function setTokenMapping(address l1Token, address l2Token) 
    external onlyOwner
```

**Example**:

```solidity
// Map USDT L1 to USDT0 L2
depositor.setTokenMapping(
    0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT L1
    0x... // USDT0 L2 address
);
```

#### `withdrawYield`

Withdraws accumulated yield for a token.

```solidity
function withdrawYield(address token) 
    external onlyOwner nonReentrant
```

**Flow**:

1. Checks yield balance > 0
2. Transfers yield to owner
3. Resets yield balance

#### `notifyYieldReceived`

Callback function called by bridge when yield arrives from L2.

```solidity
function notifyYieldReceived(address token, uint256 amount) 
    external
```

**Access Control**: Only authorized yield receivers (bridge relayer)

***

## BundledYieldVaultV2\_PRODUCTION

**Network**: Ink L2\
**Purpose**: Yield strategy management and harvesting

### Overview

The L2 Vault is the core yield farming contract. It receives bridged tokens, deposits them to yield strategies (Tydro/Velodrome), harvests yield, and bridges it back to L1.

### Key Features

* ✅ Multi-strategy support (Tydro + Velodrome)
* ✅ Auto-deposit functionality
* ✅ Yield harvesting with compounding
* ✅ Cross-chain yield bridging
* ✅ Smart allocation via YieldAllocator
* ✅ Circuit breakers and rate limiting
* ✅ Gas management

### Contract Interface

```solidity
contract BundledYieldVaultV2_PRODUCTION is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    address public immutable TYDRO_POOL;
    address public immutable ACROSS_SPOKE_POOL;
    address public immutable L2_ENCODER;
    address public immutable VELO_ROUTER;
    address public immutable VELO_HELPER;
    
    address public l1Recipient;
    mapping(address => address) public tokenMapping;
    
    struct TokenStatus {
        uint128 depositedAmount;
        uint128 currentBalance;
        uint128 yieldAvailable;
        uint32 lastUpdate;
    }
    
    mapping(address => TokenStatus) public tokenStatus;
    YieldAllocator public yieldAllocator;
}
```

### Core Functions

#### `depositAvailable`

Auto-deposits newly bridged tokens to yield strategies.

```solidity
function depositAvailable(address token, bool useSmartAllocation)
    external whenNotPaused nonReentrant rateLimitCheck(token)
```

**Parameters**:

* `token`: L2 token address
* `useSmartAllocation`: If true, uses YieldAllocator for optimal strategy selection

**Flow**:

1. Checks for new token balance from bridge
2. If `useSmartAllocation` and allocator set:
   * Allocates to best strategy via YieldAllocator
3. Otherwise:
   * Deposits to Tydro (default)

**Example**:

```solidity
// Auto-deposit with smart allocation
vault.depositAvailable(usdt0, true);

// Auto-deposit to Tydro (default)
vault.depositAvailable(usdt0, false);
```

#### `depositToTydro`

Manually deposit tokens to Tydro lending pool.

```solidity
function depositToTydro(address token, uint256 amount)
    external onlyOwner whenNotPaused nonReentrant
```

**Flow**:

1. Validates token support
2. Approves Tydro pool
3. Encodes supply parameters
4. Calls Tydro supply function
5. Updates token status

**Code Snippet**:

```solidity
function depositToTydro(address token, uint256 amount) internal {
    SafeTransferLib.safeApprove(token, TYDRO_POOL, amount);
    
    bytes32 supplyArgs = IL2Encoder(L2_ENCODER).encodeSupplyParams(
        token,
        amount,
        0  // Ref code
    );
    
    IL2Pool(TYDRO_POOL).supply(supplyArgs);
    
    // Update status
    tokenStatus[token].depositedAmount += uint128(amount);
    tokenStatus[token].currentBalance = _getTydroBalance(token);
}
```

#### `harvestAndBridge`

Harvests yield and bridges a portion back to L1.

```solidity
function harvestAndBridge(
    address token,
    uint8 compoundPercent
) external onlyOwner whenNotPaused nonReentrant
```

**Parameters**:

* `token`: Token to harvest
* `compoundPercent`: Percentage to compound (0-100), remainder bridges to L1

**Flow**:

1. Calculates available yield
2. Withdraws yield from Tydro
3. Splits yield: `compoundPercent` compound, remainder bridge
4. Re-deposits compound portion
5. Bridges remainder to L1 via Across

**Example**:

```solidity
// Harvest and bridge 50% (e.g. 50% compound, 50% bridge)
vault.harvestAndBridge(usdt0, 50);
```

#### `deployToVelodrome`

Deploy tokens to Velodrome liquidity pool.

```solidity
function deployToVelodrome(LPParams memory params)
    external onlyOwner whenNotPaused nonReentrant
```

**Parameters**:

```solidity
struct LPParams {
    address tokenA;
    address tokenB;
    uint256 amountA;
    uint256 amountB;
    bool stable;        // Stable or volatile pair
    bool stakeInGauge;  // Stake LP tokens in gauge
}
```

**Flow**:

1. Validates pair exists
2. Approves Velodrome router
3. Adds liquidity via router
4. Optionally stakes in gauge
5. Updates token status

***

## YieldVaultFactory

**Network**: Ink L2\
**Purpose**: Deploy private vault instances for users

### Overview

The Factory contract enables users to deploy their own isolated vault instances. Each vault is fully owned by the deployer and operates independently.

### Key Features

* ✅ One-click vault deployment
* ✅ Ownership transfer to deployer
* ✅ Vault tracking and indexing
* ✅ Configurable default settings

### Contract Interface

```solidity
contract YieldVaultFactory {
    struct VaultConfig {
        address tydroPool;
        address l2Encoder;
        address acrossSpokePool;
        address veloRouter;
    }
    
    VaultConfig public defaultConfig;
    address[] public deployedVaults;
    mapping(address => address) public vaultOwners;
    mapping(address => address[]) public ownerVaults;
}
```

### Core Functions

#### `deployVault`

Deploys a new vault instance for the caller.

```solidity
function deployVault(address l1Recipient) 
    external returns (address vault)
```

**Parameters**:

* `l1Recipient`: L1Depositor address that will receive bridged yield

**Flow**:

1. Validates l1Recipient
2. Deploys new `BundledYieldVaultV2_PRODUCTION` instance
3. Transfers ownership to deployer (msg.sender)
4. Tracks deployment
5. Returns vault address

**Example**:

```solidity
// Deploy your own vault
address myVault = factory.deployVault(l1DepositorAddress);

// Vault is now owned by msg.sender
// You have full control over this vault
```

#### `getVaultsForOwner`

Get all vaults deployed by a specific owner.

```solidity
function getVaultsForOwner(address owner) 
    external view returns (address[] memory)
```

***

## YieldAllocator

**Network**: Ink L2\
**Purpose**: Smart multi-strategy allocation system

### Overview

The YieldAllocator enables dynamic allocation of funds across multiple yield strategies based on APY and risk preferences.

### Key Features

* ✅ Multi-strategy registration
* ✅ APY-based allocation
* ✅ Automatic rebalancing
* ✅ Auto-compounding
* ✅ Configurable allocation limits

### Contract Interface

```solidity
contract YieldAllocator is Ownable, ReentrancyGuard {
    mapping(uint8 => IYieldStrategy) public strategies;
    
    struct StrategyAllocation {
        uint128 principal;
        uint64 maxAllocationBps;
        uint32 lastRebalance;
    }
    
    mapping(address => mapping(uint8 => StrategyAllocation)) public allocations;
}
```

### Core Functions

#### `allocateFunds`

Allocates funds to optimal strategy.

```solidity
function allocateFunds(
    address token,
    uint256 amount,
    uint8 forceStrategy
) external onlyOwner nonReentrant
```

**Parameters**:

* `token`: Token to allocate
* `amount`: Amount to allocate
* `forceStrategy`: Strategy ID to force (0 = auto-select)

**Flow**:

1. If `forceStrategy > 0`: Allocate to specified strategy
2. Otherwise: Compare APYs and allocate to best strategy
3. Respects max allocation limits
4. Deposits to selected strategy

#### `rebalance`

Rebalances funds between strategies.

```solidity
function rebalance(
    address token,
    uint8 fromStrategy,
    uint8 toStrategy,
    uint256 amount
) external onlyOwner nonReentrant
```

**Flow**:

1. Checks rebalance threshold (yield differential)
2. Withdraws from source strategy
3. Allocates to destination strategy
4. Updates allocation tracking

***

## 🔐 Security Features

All contracts implement:

* **Ownable**: Owner-only operations
* **ReentrancyGuard**: Protection against reentrancy attacks
* **Pausable**: Emergency pause functionality
* **Rate Limiting**: Anti-spam mechanisms
* **Circuit Breakers**: Withdrawal limits and emergency stops

***

## 📊 Gas Costs

Typical gas costs (approximate):

| Operation               | Gas Cost    |
| ----------------------- | ----------- |
| `depositToL2` (L1)      | \~77,000    |
| `depositAvailable` (L2) | \~120,000   |
| `harvestAndBridge` (L2) | \~180,000   |
| `deployVault` (Factory) | \~2,500,000 |

***

## 🔗 Related Documentation

* [Architecture Overview](../architecture/)
* [Factory & Deployment](../factory/)
* [Yield Strategies](../architecture/yield-strategies/strategies.md)
* [Bridge Integration](../bridge/)
