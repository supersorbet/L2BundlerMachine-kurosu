// Configuration for Yield Terminal
export const CONFIG = {
  // Contract addresses (update these with your deployed addresses)
  L2_VAULT: "0x6CcF950e1Ea79a5B32EE0D347896115C23092fa1",
  L1_DEPOSITOR: "0xaA1be5133e5dBC9AA5539D29C939DCbb8FD5B110",
  
  // Token addresses
  USDT_L1: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  USDT0_L2: "0x0200C29006150606B650577BBE7B6248F58470c1",
  WETH_L2: "0x4200000000000000000000000000000000000006",
  
  // Network configs
  ETH_CHAIN_ID: 1,
  INK_CHAIN_ID: 57073,
  
  // Token decimals
  USDT_DECIMALS: 6,
  ETH_DECIMALS: 18,
};

// ABI snippets for contract interactions
export const ABIS = {
  ERC20: [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function approve(address,uint256) returns (bool)",
    "function allowance(address,address) view returns (uint256)",
  ],
  
  L2_VAULT: [
    "function owner() view returns (address)",
    "function l1Recipient() view returns (address)",
    "function tokenMapping(address) view returns (address)",
    "function paused() view returns (bool)",
    "function emergencyMode() view returns (bool)",
    "function breakerActive() view returns (bool)",
    "function minGasBalance() view returns (uint128)",
    "function defaultSlippageBps() view returns (uint64)",
    "function autoGasRefillBps() view returns (uint64)",
    "function getStatus(address) view returns (uint256 depositedAmount, uint256 currentBalance, uint256 yieldAvailable, uint256 gasBalance)",
    "function getYieldAvailable(address) view returns (uint256)",
    "function getCurrentAPY(address) view returns (uint256)",
    "function getVaultHealth(address) view returns (bool isHealthy, bool hasGas, bool hasYield, uint256 timeSinceLastUpdate, uint256 totalValueLocked)",
    "function canPerformOp(address) view returns (bool canOperate, string memory reason)",
    "function deposit(address token, uint256 amount)",
    "function depositAvailable(address token, bool useSmartAllocation)",
    "function depositAvailable(address token)",
    "function harvestAndBridge(address token, uint8 compoundPercent, uint64 customSlippageBps, uint256 minBridgeAmount)",
    "function depositAndHarvest(address token, uint8 compoundPercent, uint64 customSlippageBps, uint256 minBridgeAmount)",
    "function updateYield(address token)",
    "function momoCompound(address token, uint256 minYieldThreshold)",
    "function smartRebalance(address token)",
    "function smartCompound(address token)",
    "function getBestStrategy(address token) view returns (uint8 strategyId, uint256 apyBps)",
    "function getATokenAddress(address token) view returns (address)",
    "function estimateBridgeFee(address token, uint256 amount) view returns (uint256 estimatedFee)",
    "function findBestYieldToken(address[] calldata tokens) view returns (address bestToken, uint256 bestAPY)",
    "function getTotalValueLocked(address[] calldata tokens) view returns (uint256 total)",
    "function pause()",
    "function unpause()",
    "function activateEmsMode()",
    "function deactivateEmsMode()",
    "function activateBreaker()",
    "function deactivateBreaker()",
    "function setMinGasBal(uint128 _minGasBalance)",
    "function setDefaultSlippage(uint64 _slippageBps)",
    "function setAutoRefill(uint64 _autoGasRefillBps)",
    "function setMaxDeposit(address token, uint128 maxAmount)",
    "function mapToken(address l2Token, address l1Token)",
    "function setL1Recipient(address _l1Recipient)",
    "function getVeloGauge(address tokenA, address tokenB, bool stable) view returns (address)",
  ],
  
  L1_DEPOSITOR: [
    "function owner() view returns (address)",
    "function l2Vault() view returns (address)",
    "function tokenMapping(address) view returns (address)",
    "function paused() view returns (bool)",
    "function maxSlippageBps() view returns (uint64)",
    "function minDepositAmount() view returns (uint128)",
    "function totalDeposits(address) view returns (uint256)",
    "function yieldBalance(address) view returns (uint256)",
    "function depositToL2(address token, uint256 amount, uint256 minAmount)",
    "function withdrawYield(address token, address to)",
  ],
};

