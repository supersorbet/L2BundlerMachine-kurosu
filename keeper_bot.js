#!/usr/bin/env node

/**
 * Monitors vault health and automatically harvests yield when threshold is met.
 * Designed for testing and can be adapted for production use with Gelato/Chainlink.
 * 
 * Usage:
 *   node keeper_bot.js --network ink --rpc <RPC_URL> --vault <VAULT_ADDRESS>
 * 
 * Environment Variables:
 *   KEEPER_PRIVATE_KEY - Private key for keeper (optional, uses default for testing)
 *   RPC_URL - RPC endpoint (can also use --rpc flag)
 *   VAULT_ADDRESS - Vault contract address (can also use --vault flag)
 */

const { ethers } = require('ethers');
const { program } = require('commander');
const DEFAULT_INTERVALS = {
    updateYield: 3600,      // 1 hour
    checkHarvest: 21600,    // 6 hours
    checkGas: 86400         // 24 hours
};

const VAULT_ABI = [
    "function updateYield(address token) external",
    "function autoHarvestAndBridge(address token) external",
    "function autoHarvestAll(address[] calldata tokens) external",
    "function depositAvailable(address token) external",
    "function getVaultHealth(address token) external view returns (bool isHealthy, bool hasGas, bool hasYield, uint256 timeSinceLastUpdate, uint256 totalValueLocked)",
    "function tokenStatus(address token) external view returns (uint128 depositedAmount, uint128 currentBalance, uint128 yieldAvailable, uint32 lastUpdate)",
    "function minYieldThresholdBps() external view returns (uint64)",
    "function defaultCompoundPercent() external view returns (uint8)",
    "function minGasBalance() external view returns (uint128)",
    "event YieldUpdated(address indexed token, uint256 yield)",
    "event AutoHarvested(address indexed token, bool success)",
    "event YieldBridged(address indexed token, uint256 amount)"
];

class KeeperBot {
    constructor(config) {
        this.config = config;
        this.provider = new ethers.providers.JsonRpcProvider(config.rpc);
        this.wallet = config.privateKey 
            ? new ethers.Wallet(config.privateKey, this.provider)
            : ethers.Wallet.createRandom().connect(this.provider);
        // Support single vault or multiple vaults
        if (config.vaultAddress) {
            // Single vault mode (backward compatible)
            this.vaults = [new ethers.Contract(config.vaultAddress, VAULT_ABI, this.wallet)];
        } else if (config.vaultAddresses && config.vaultAddresses.length > 0) {
            // Multi-vault mode
            this.vaults = config.vaultAddresses.map(addr => 
                new ethers.Contract(addr, VAULT_ABI, this.wallet)
            );
        } else {
            throw new Error('Either vaultAddress or vaultAddresses must be provided');
        }
        
        this.tokens = config.tokens || [];
        this.running = false;
        this.batchSize = config.batchSize || 200; // Default batch size for large vault counts
        this.stats = {
            yieldUpdates: 0,
            harvests: 0,
            failures: 0,
            lastUpdate: null,
            lastHarvest: null,
            vaultsMonitored: this.vaults.length
        };
    }

    async start() {
        console.log(' Keeper Starting **************');
        console.log('Network:', this.config.network || 'unknown');
        console.log('Vaults:', this.vaults.length, this.vaults.length === 1 ? 'vault' : 'vaults');
        if (this.vaults.length === 1) {
            console.log('Vault Address:', this.vaults[0].address);
        } else {
            console.log('Vault Addresses:', this.vaults.map(v => v.address).join(', '));
        }
        console.log('Keeper Address:', this.wallet.address);
        console.log('Tokens:', this.tokens.length);
        console.log('');

        const balance = await this.provider.getBalance(this.wallet.address);
        console.log('Keeper Balance:', ethers.utils.formatEther(balance), 'ETH');
        if (balance.lt(ethers.utils.parseEther('0.01'))) {
            console.warn('WARNING: Low keeper balance! Bot needs ETH.');
            console.warn('  Fund this address:', this.wallet.address);
        }

        // Verify all vault contracts exist
        for (let i = 0; i < this.vaults.length; i++) {
            const vaultAddress = this.vaults[i].address;
            const code = await this.provider.getCode(vaultAddress);
            if (code === '0x') {
                console.error(`ERROR: No contract code at vault ${i + 1} address!`);
                console.error('  Vault address:', vaultAddress);
                console.error('  Please verify the address is correct.');
                process.exit(1);
            } else {
                console.log(`✓ Vault ${i + 1} verified (${(code.length - 2) / 2} bytes)`);
            }
        }
        console.log('');
        // Try to read config from first vault (as example)
        if (this.vaults.length > 0) {
            await this.printVaultConfig(this.vaults[0]);
        }

        this.running = true;
        this.startYieldUpdateInterval();
        this.startHarvestCheckInterval();
        this.startGasCheckInterval();
        this.setupEventListeners();

        console.log('Keeper bot running... (Ctrl+C to stop)');
    }

    async printVaultConfig(vault) {
        try {
            // callStatic for view functions to avoid gas estimation issues
            const minThreshold = await vault.callStatic.minYieldThresholdBps();
            const compoundPercent = await vault.callStatic.defaultCompoundPercent();
            const minGas = await vault.callStatic.minGasBalance();
            
            console.log('Vault Configuration (example from first vault):');
            console.log('  Min Yield Threshold:', minThreshold.toString(), 'bps (', (minThreshold / 100).toFixed(2), '%)');
            console.log('  Default Compound %:', compoundPercent.toString(), '%');
            console.log('  Min Gas Balance:', ethers.utils.formatEther(minGas), 'ETH');
            console.log('');
        } catch (error) {
            console.error('Error reading vault config:', error.message);
            console.error('  This might indicate the vault address is incorrect or contract not deployed');
        }
    }

    startYieldUpdateInterval() {
        const interval = this.config.intervals?.updateYield || DEFAULT_INTERVALS.updateYield;
        console.log(`Starting yield update interval: every ${interval}s`);
        
        setInterval(async () => {
            if (!this.running) return;
            await this.updateAllYields();
        }, interval * 1000);

        setTimeout(() => this.updateAllYields(), 5000);
    }

    startHarvestCheckInterval() {
        const interval = this.config.intervals?.checkHarvest || DEFAULT_INTERVALS.checkHarvest;
        console.log(`Starting harvest check interval: every ${interval}s`);
        
        setInterval(async () => {
            if (!this.running) return;
            await this.checkAndHarvest();
        }, interval * 1000);
        setTimeout(() => this.checkAndHarvest(), 10000);
    }

    startGasCheckInterval() {
        const interval = this.config.intervals?.checkGas || DEFAULT_INTERVALS.checkGas;
        console.log(`Starting gas check interval: every ${interval}s`);
        
        setInterval(async () => {
            if (!this.running) return;
            await this.checkGasBalance();
        }, interval * 1000);
    }

    setupEventListeners() {
        this.vault.on('YieldUpdated', (token, yieldAmount, event) => {
            console.log(`[EVENT] YieldUpdated: ${token} = ${ethers.utils.formatUnits(yieldAmount, 6)}`);
        });

        this.vault.on('AutoHarvested', (token, success, event) => {
            if (success) {
                console.log(`[EVENT] AutoHarvested: ${token} - SUCCESS`);
                this.stats.harvests++;
            } else {
                console.log(`[EVENT] AutoHarvested: ${token} - FAILED`);
                this.stats.failures++;
            }
        });

        this.vault.on('YieldBridged', (token, amount, event) => {
            console.log(`[EVENT] YieldBridged: ${token} = ${ethers.utils.formatUnits(amount, 6)}`);
        });
    }

    async updateAllYields() {
        console.log(`[${new Date().toISOString()}] Updating yields for ${this.vaults.length} vault(s), ${this.tokens.length} token(s)...`);
        // Check keeper gas once
        const keeperBalance = await this.provider.getBalance(this.wallet.address);
        if (keeperBalance.lt(ethers.utils.parseEther('0.001'))) {
            console.error(`  ✗ Skipping: Keeper has insufficient gas (${ethers.utils.formatEther(keeperBalance)} ETH)`);
            return;
        }
        // Batch processing for large vault counts (200 vaults per batch)
        const BATCH_SIZE = this.config.batchSize || 200;
        const batches = this._chunkArray(this.vaults, BATCH_SIZE);
        if (batches.length > 1) {
            console.log(`  Processing in ${batches.length} batches of ~${BATCH_SIZE} vaults each`);
        }
        for (let batchIdx = 0; batchIdx < batches.length; batchIdx++) {
            const batch = batches[batchIdx];
            if (batches.length > 1) {
                console.log(`  Batch ${batchIdx + 1}/${batches.length}: ${batch.length} vaults`);
            }
            
            for (let v = 0; v < batch.length; v++) {
                const vault = batch[v];
                const vaultLabel = this.vaults.length > 1 ? `Vault ${batchIdx * BATCH_SIZE + v + 1}` : 'Vault';
                for (const token of this.tokens) {
                    try {
                        const gasEstimate = await vault.estimateGas.updateYield(token).catch(() => null);
                        if (!gasEstimate) {
                            if (this.vaults.length <= 10) { // Only log details for small vault counts
                                console.log(`  ⚠ ${vaultLabel} - Could not estimate gas for ${token.slice(0, 10)}...`);
                            }
                            continue;
                        }

                        const tx = await vault.updateYield(token, {
                            gasLimit: gasEstimate.mul(120).div(100) // Add 20% buffer
                        });
                        const receipt = await tx.wait();
                        if (this.vaults.length <= 10) { // Only log details for small vault counts
                            console.log(`  ✓ ${vaultLabel} - Yield updated for ${token.slice(0, 10)}... (gas: ${receipt.gasUsed.toString()})`);
                        }
                        this.stats.yieldUpdates++;
                        this.stats.lastUpdate = new Date();
                    } catch (error) {
                        // Skip failed vaults/tokens, continue with others
                        if (error.code !== 'UNPREDICTABLE_GAS_LIMIT' && error.code !== 'CALL_EXCEPTION') {
                            if (this.vaults.length <= 10) { // Only log details for small vault counts
                                console.error(`  ✗ ${vaultLabel} - Failed: ${error.message.slice(0, 50)}`);
                            }
                        }
                        this.stats.failures++;
                    }
                }
            }
        
            if (batchIdx < batches.length - 1) {
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }
        
        if (this.vaults.length > 10) {
            console.log(`  ✓ Updated ${this.stats.yieldUpdates} yield(s) across ${this.vaults.length} vault(s)`);
        }
        console.log('');
    }
    
    _chunkArray(array, size) {
        const chunks = [];
        for (let i = 0; i < array.length; i += size) {
            chunks.push(array.slice(i, i + size));
        }
        return chunks;
    }

    async checkAndHarvest() {
        console.log(`[${new Date().toISOString()}] Checking harvest conditions for ${this.vaults.length} vault(s)...`);
        let totalHarvests = 0;
        for (let v = 0; v < this.vaults.length; v++) {
            const vault = this.vaults[v];
            const vaultLabel = this.vaults.length > 1 ? `Vault ${v + 1}` : 'Vault';
            
            for (const token of this.tokens) {
                try {
                    // Use callStatic for view functions
                    const [status, health] = await Promise.all([
                        vault.callStatic.tokenStatus(token).catch(() => null),
                        vault.callStatic.getVaultHealth(token).catch(() => null)
                    ]);
                    if (!status || !health) {
                        continue; // Skip if can't read
                    }

                    const { depositedAmount, yieldAvailable } = status;
                    const { isHealthy, hasGas, hasYield } = health;
                    const minThreshold = await vault.callStatic.minYieldThresholdBps().catch(() => null);
                    if (!minThreshold) {
                        continue;
                    }
                    const threshold = depositedAmount.mul(minThreshold).div(10000);
                    if (yieldAvailable.gte(threshold) && isHealthy && hasGas) {
                        console.log(`  ${vaultLabel} - Token ${token.slice(0, 10)}... ready (yield: ${ethers.utils.formatUnits(yieldAvailable, 6)})`);
                        // Harvest from this vault
                        try {
                            const tx = await vault.autoHarvestAndBridge(token);
                            const receipt = await tx.wait();
                            console.log(`  ✓ ${vaultLabel} - Harvested! Gas: ${receipt.gasUsed.toString()}`);
                            totalHarvests++;
                            this.stats.harvests++;
                            this.stats.lastHarvest = new Date();
                        } catch (error) {
                            console.error(`  ✗ ${vaultLabel} - Harvest failed: ${error.message.slice(0, 50)}`);
                            this.stats.failures++;
                        }
                    }
                } catch (error) {
                    this.stats.failures++;
                }
            }
        }

        if (totalHarvests === 0) {
            console.log(`  No vaults ready for harvest`);
        } else {
            console.log(`  Total harvests: ${totalHarvests}`);
        }
        console.log('');
    }

    async checkGasBalance() {
        console.log(`[${new Date().toISOString()}] Checking gas balances for ${this.vaults.length} vault(s)...`);
        
        for (let v = 0; v < this.vaults.length; v++) {
            const vault = this.vaults[v];
            const vaultLabel = this.vaults.length > 1 ? `Vault ${v + 1}` : 'Vault';
            
            try {
                const minGas = await vault.callStatic.minGasBalance().catch(() => null);
                if (!minGas) {
                    continue;
                }
                
                const vaultBalance = await this.provider.getBalance(vault.address);
                
                console.log(`  ${vaultLabel}: ${ethers.utils.formatEther(vaultBalance)} ETH (min: ${ethers.utils.formatEther(minGas)} ETH)`);
                
                if (vaultBalance.lt(minGas)) {
                    console.warn(`    ⚠ WARNING: Below minimum!`);
                }
            } catch (error) {
                console.error(`  ✗ ${vaultLabel} - Error: ${error.message.slice(0, 50)}`);
            }
        }
        console.log('');
    }

    printStats() {
        console.log('\n=== Keeper Bot Statistics ===');
        console.log('Vaults Monitored:', this.stats.vaultsMonitored);
        console.log('Yield Updates:', this.stats.yieldUpdates);
        console.log('Harvests:', this.stats.harvests);
        console.log('Failures:', this.stats.failures);
        console.log('Last Update:', this.stats.lastUpdate || 'Never');
        console.log('Last Harvest:', this.stats.lastHarvest || 'Never');
        console.log('');
    }

    stop() {
        console.log('\n=== Stopping Keeper Bot ===');
        this.running = false;
        this.printStats();
        process.exit(0);
    }
}

// CLI
program
    .name('keeper_bot')
    .description('Keeper bot for L2 Yield Vault automation (supports single or multiple vaults)')
    .option('-n, --network <network>', 'Network name (ink, mainnet, etc.)', 'ink')
    .option('-r, --rpc <url>', 'RPC URL')
    .option('-v, --vault <address>', 'Single vault contract address (for backward compatibility)')
    .option('--vaults <addresses>', 'Comma-separated vault addresses (for multi-vault mode)')
    .option('-t, --tokens <addresses>', 'Comma-separated token addresses')
    .option('-k, --key <key>', 'Private key (or use KEEPER_PRIVATE_KEY env var)')
    .option('--update-interval <seconds>', 'Yield update interval', '3600')
    .option('--harvest-interval <seconds>', 'Harvest check interval', '21600')
    .option('--gas-interval <seconds>', 'Gas check interval', '86400')
    .option('--batch-size <number>', 'Batch size for processing vaults (default: 200)', '200')
    .parse(process.argv);

const options = program.opts();
if (!options.rpc && !process.env.RPC_URL) {
    console.error('Error: RPC URL required (--rpc or RPC_URL env var)');
    process.exit(1);
}

// Support single vault or multiple vaults
let vaultAddresses = [];
if (options.vaults) {
    // Multi-vault mode
    vaultAddresses = options.vaults.split(',').map(a => a.trim());
} else if (options.vault) {
    // Single vault mode (backward compatible)
    vaultAddresses = [options.vault];
} else if (process.env.VAULT_ADDRESSES) {
    // Multi-vault from env
    vaultAddresses = process.env.VAULT_ADDRESSES.split(',').map(a => a.trim());
} else if (process.env.VAULT_ADDRESS) {
    // Single vault from env (backward compatible)
    vaultAddresses = [process.env.VAULT_ADDRESS];
} else {
    console.error('Error: Vault address(es) required');
    console.error('  Use --vault <address> for single vault');
    console.error('  Use --vaults <addr1,addr2,...> for multiple vaults');
    console.error('  Or set VAULT_ADDRESS or VAULT_ADDRESSES env var');
    process.exit(1);
}

const tokens = options.tokens 
    ? options.tokens.split(',').map(t => t.trim())
    : (process.env.TOKENS ? process.env.TOKENS.split(',').map(t => t.trim()) : []);
if (tokens.length === 0) {
    console.warn('Warning: No tokens specified. Bot will run but won\'t perform operations.');
}

const config = {
    network: options.network,
    rpc: options.rpc || process.env.RPC_URL,
    vaultAddress: vaultAddresses.length === 1 ? vaultAddresses[0] : undefined, // For backward compat
    vaultAddresses: vaultAddresses.length > 1 ? vaultAddresses : undefined, // Multi-vault mode
    tokens: tokens,
    privateKey: options.key || process.env.KEEPER_PRIVATE_KEY,
    batchSize: parseInt(options.batchSize) || parseInt(process.env.BATCH_SIZE) || 200,
    intervals: {
        updateYield: parseInt(options.updateInterval),
        checkHarvest: parseInt(options.harvestInterval),
        checkGas: parseInt(options.gasInterval)
    }
};

const bot = new KeeperBot(config);
process.on('SIGINT', () => bot.stop());
process.on('SIGTERM', () => bot.stop());

bot.start().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
});

