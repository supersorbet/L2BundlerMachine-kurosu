# Contract Mechanics

## Overview

Modular contract architecture enabling cross-chain yield farming:

**Core Contracts**: `L1DepositorV2_` (L1) and `BundledYieldVaultV2_` (L2)

**Helper Contracts**: `VelodromeHelper` (LP operations), `SlipstreamHelper` (V3 positions), `YieldAllocator` (smart allocation), `YieldVaultFactory` (vault deployment)

**Status**: V1 deployed on Ink L2 mainnet ([`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs)). V2 adds multi-strategy support and helper contracts.

See [Version History](./versions.md) for comparison.

---

## L1DepositorV2_

**Contract**: `L1DepositorV2_.sol`  
**Location**: Ethereum Mainnet  
**Purpose**: Entry point for user deposits and yield management

### Key Functions

```solidity
function depositToL2(address token, uint256 amount, uint256 minAmount)
function withdrawYield(address token)
function setTokenMapping(address l1Token, address l2Token)
```

### Storage

- `tokenMapping`: Maps L1 token addresses to L2 token addresses
- `yieldBalance`: Tracks accumulated yield per token
- `l2Vault`: Address of the L2 vault contract
- `maxSlippageBps`: Maximum slippage tolerance (basis points)

---

## BundledYieldVault (V1/V2)

**Contract**: `BundledYieldVaultV2_.sol`  
**Location**: Ink L2  
**Purpose**: Yield strategy management and harvesting

### V1

**Deployed Address**: [`0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7`](https://explorer.inkonchain.com/address/0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7?tab=txs)

**Capabilities**:
- Receive bridged tokens from L1
- Auto-deposit to Tydro lending pools
- Harvest and bridge yield back to L1

### V2

**Contract**: `BundledYieldVaultV2_.sol`

**Capabilities**:
- Receive bridged tokens and auto-deposit to strategies (Tydro/Velodrome/Slipstream)
- Harvest yield with flexible compounding options
- Bridge yield back to L1 via Across Protocol
- Smart allocation via YieldAllocator integration
- LP operations through VelodromeHelper (zap, stake, harvest)
- V3 position management via SlipstreamHelper

### Key Functions

**Main Vault** (`BundledYieldVaultV2_`):
```solidity
// Deposits
function depositAvailable(address token, bool useSmartAllocation)
function deposit(address token, uint256 amount)

// Yield operations
function harvestAndBridge(address token, uint8 compoundPercent, uint64 customSlippageBps, uint256 minBridgeAmount)
function autoHarvestAndBridge(address token)
function momoCompound(address token, uint256 minYieldThreshold)

// Velodrome operations
function createVelodromeLP(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bool stable, bool stakeInGauge, bool sendToOwner)
function zapIntoLP(address tokenIn, address tokenOut, uint256 amountIn, bool stable, bool stakeInGauge, uint256 minLiquidity, bool sendToOwner)
function harvestVelodromeRewards(bytes32 pairHash)
function harvestVelodromeFees(address tokenA, address tokenB, bool stable)

// Slipstream operations
function createSlipstreamPosition(SlipstreamMintParams calldata params, bool stakeInGauge)
function increaseSlipstreamLiquidity(SlipstreamLiquidityParams calldata params)
function decreaseSlipstreamLiquidity(SlipstreamDecreaseParams calldata params)
function harvestSlipstreamRewards(address token0, address token1, uint24 fee)
function stakeSlipstreamPosition(uint256 tokenId, address token0, address token1, uint24 fee)

// Smart allocation
function smartRebalance(address token)
function smartCompound(address token)
function getBestStrategy(address token) returns (uint8 strategyId, uint256 apyBps)
```

**VelodromeHelper** (via vault):
```solidity
// LP operations
function createLP(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bool stable, bool stakeInGauge)
function zapIntoLP(address tokenIn, address tokenOut, uint256 amountIn, bool stable, bool stakeInGauge, uint256 minLiquidity)

// Rewards
function harvestRewards(bytes32 pairHash)
function harvestFees(address tokenA, address tokenB, bool stable)

// Staking
function unstakeLP(bytes32 pairHash, uint256 amount)
```

**SlipstreamHelper** (via vault):
```solidity
function createPosition(MintParams calldata params, bool stakeInGauge)
function increaseLiquidity(uint256 tokenId, IncreaseLiquidityParams calldata params)
function decreaseLiquidity(uint256 tokenId, DecreaseLiquidityParams calldata params)
function harvestRewards(bytes32 positionHash)
function stakePosition(uint256 tokenId, bytes32 positionHash)
function unstakePosition(uint256 tokenId, bytes32 positionHash)
```

### Storage

- `tokenStatus`: Comprehensive status tracking per token (deposited amount, current balance, yield available, last update)
- `tokenMapping`: Maps L2 token addresses to L1 token addresses
- `l1Recipient`: Address of the L1 depositor contract

---

## Contract Architecture

### Deployment Flow

1. **Factory Deploys Vault**: `YieldVaultFactory.deployVault()` creates new `BundledYieldVaultV2_`
2. **Helper Deployment**: Vault constructor automatically deploys `VelodromeHelper` and `SlipstreamHelper`
3. **Helper Setup**: Helpers are configured with vault address (vault-only access)
4. **Allocator Setup**: Optional `YieldAllocator` can be set via `setAllocator()`

### Contract Interaction Flow

**Deposit Flow**:
1. **L1 → L2**: `L1DepositorV2_.depositToL2()` bridges tokens via Across
2. **Auto-Deposit**: `BundledYieldVaultV2_.depositAvailable()` detects bridged tokens
3. **Strategy Allocation**: If `useSmartAllocation=true`, calls `YieldAllocator.allocateFunds()`
4. **Helper Operations**: For Velodrome/Slipstream, vault calls helper contracts

**Harvest Flow**:
1. **Yield Detection**: Vault updates yield via `_updateYield()`
2. **Harvest**: `harvestAndBridge()` withdraws from strategies
3. **Split**: Yield split between compound and bridge portions
4. **Bridge**: Bridge portion sent to L1 via Across SpokePool
5. **L1 Receipt**: `L1DepositorV2_.receiveYield()` updates yield balance

**LP Operations**:
1. **Vault Calls Helper**: `createVelodromeLP()` or `zapIntoLP()` transfers tokens to helper
2. **Helper Executes**: Helper performs LP operations via Velodrome Router
3. **LP Management**: Helper tracks LP balances and staking state
4. **Rewards**: Vault calls helper to harvest rewards and fees

All operations are **owner-only** for security, ensuring only authorized parties can interact with the system.

---

## Helper Contracts (V2)

### VelodromeHelper

Includes peripheral zap utility contracts that simplify complex DeFi operations into single transactions. These contracts work alongside the main vault to provide seamless user experiences.

**Key Features**:
- ✅ **Create LP**: Add liquidity to Velodrome pools (stable or volatile)
- ✅ **Zap Into LP**: One-click zap - swap single token and add to LP in one transaction
- ✅ **Harvest Rewards**: Collect VELO rewards from staked LP positions
- ✅ **Harvest Fees**: Collect trading fees from LP positions
- ✅ **Stake/Unstake**: Manage LP token staking in Velodrome gauges

**Integration**: Deployed automatically in `BundledYieldVaultV2_` constructor and set as vault-only access.

**Zap Functionality**:
- `zapIntoLP()`: Takes a single token, swaps half to the pair token, and adds liquidity
- Uses Velodrome Universal Router for optimal routing
- Supports both stable and volatile pairs
- Optional automatic staking in gauge for VELO rewards

### SlipstreamHelper

**Contract**: `SlipstreamHelper.sol`  
**Purpose**: Manages Slipstream V3 concentrated liquidity positions

**Key Features**:
- ✅ **Create Position**: Mint NFT positions with custom tick ranges
- ✅ **Increase Liquidity**: Add more liquidity to existing positions
- ✅ **Decrease Liquidity**: Remove liquidity from positions
- ✅ **Collect Fees**: Harvest trading fees from positions
- ✅ **Stake Positions**: Stake NFT positions in LeafCLGauge for rewards
- ✅ **Harvest Rewards**: Collect rewards from staked positions

**Integration**: Deployed automatically in `BundledYieldVaultV2_` constructor and set as vault-only access.

**Position Management**:
- Each position is an ERC-721 NFT.
- Positions tracked by position hash (token0, token1, fee)
- Supports multiple positions per pool
- Automatic fee collection and reward harvesting

---

## YieldAllocator

**Contract**: `YieldAllocator.sol`  
**Purpose**: Smart multi-strategy allocation system

**Key Features**:
- ✅ **Strategy Registration**: Register multiple yield strategies
- ✅ **Auto-Allocation**: Automatically allocate funds to highest-yielding strategy
- ✅ **Auto-Rebalance**: Rebalance when yield differential exceeds threshold
- ✅ **Smart Compound**: Harvest and reinvest in best strategy
- ✅ **APY Comparison**: Compare yields across strategies

**Integration**: Set via `setAllocator()` on the vault. Used when `useSmartAllocation=true` in `depositAvailable()`.

**Strategy Interface**: Strategies implement `IYieldStrategy`:
- `deposit()`: Deposit tokens to strategy
- `withdraw()`: Withdraw from strategy
- `harvest()`: Harvest yield
- `getAPY()`: Get current APY
- `getBalance()`: Get current balance

---

## YieldVaultFactory

**Contract**: `YieldVaultFactory.sol`  
**Purpose**: Deploy user-owned vault instances

**Key Features**:
- ✅ **Deploy Vault**: Create new `BundledYieldVaultV2_` instance
- ✅ **Ownership Transfer**: Automatically transfers ownership to deployer
- ✅ **Vault Tracking**: Tracks all deployed vaults and owner mappings
- ✅ **Default Config**: Uses factory's default configuration

**Usage**:
```solidity
function deployVault(address l1Recipient) external returns (address vault)
```

**Benefits**:
- Each user gets isolated vault instance
- Full ownership and control
- Independent configuration
- No shared state or risks

---

## Development & Funding

**Current State**: Core contracts deployed and operational. Helper contracts integrated in V2.

**Future Enhancements** (require funding):
- Decentralized keeper network for full automation
- Additional protocol integrations (Curve Finance priority)
- Enhanced analytics and monitoring tools
- Web application for user interface

See [Roadmap](../ROADMAP.md) for detailed development plans.

---

## Related Documentation

- [User Flows](./user-flows.md) - Contract interaction flows
- [Security Architecture](./security.md) - Security mechanisms
- [Storage Layout](./storage.md) - Data structures

