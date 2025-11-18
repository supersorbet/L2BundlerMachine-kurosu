import { useMemo } from 'react'
import { ethers } from 'ethers'
import { CONFIG } from '../config'
import { COMMAND_METADATA } from '../commands/metadata'

export function useTerminalCommands({ contracts, addOutput, setLoading, onStatusUpdate }) {
  return useMemo(() => {
    if (!contracts) return {}

    const refreshStatus = () => {
      if (typeof onStatusUpdate === 'function') {
        onStatusUpdate()
      }
    }

    const withLoading = async (fn) => {
      setLoading(true)
      try {
        await fn()
      } finally {
        setLoading(false)
      }
    }

    const parseAmount = (args, commandName) => {
      if (!args.length) {
        addOutput('error', `Usage: ${COMMAND_METADATA[commandName].usage}`)
        return null
      }
      const amount = parseFloat(args[0])
      if (Number.isNaN(amount) || amount <= 0) {
        addOutput('error', 'Invalid amount')
        return null
      }
      return amount
    }

    const status = async () => {
      addOutput('info', 'Fetching vault status...')
      const status = await contracts.getVaultStatus()
      if (!status) {
        addOutput('error', 'Unable to fetch status')
        return
      }
      addOutput('success', `Deposited: ${parseFloat(status.deposited).toFixed(2)} USDT0`)
      addOutput('success', `Current: ${parseFloat(status.current).toFixed(2)} USDT0`)
      addOutput('success', `Yield: ${parseFloat(status.yieldAmount).toFixed(2)} USDT0`)
      addOutput('success', `Gas: ${parseFloat(status.gas).toFixed(6)} ETH`)
      refreshStatus()
    }

    const balances = async () => {
      try {
        addOutput('info', 'Fetching balances...')
        const signer = contracts.l2Vault.signer || contracts.l1Depositor.signer
        if (!signer) {
          addOutput('error', 'Wallet not connected to signer')
          return
        }
        const address = await signer.getAddress()
        const [ethBalance, usdt0Balance, vaultBalance] = await Promise.all([
          contracts.getETHBalance(address),
          contracts.getBalance(CONFIG.USDT0_L2, address),
          contracts.getBalance(CONFIG.USDT0_L2, CONFIG.L2_VAULT),
        ])
        addOutput('success', `Wallet L2 ETH: ${parseFloat(ethBalance).toFixed(6)} ETH`)
        addOutput('success', `Wallet USDT0: ${parseFloat(usdt0Balance).toFixed(2)} USDT0`)
        addOutput('info', `Vault USDT0 balance: ${parseFloat(vaultBalance).toFixed(2)} USDT0`)
      } catch {
        addOutput('error', 'Unable to fetch balances (switch network if needed)')
      }
    }

    const deposit = async ({ args }) => {
      const amount = parseAmount(args, 'deposit')
      if (!amount) return
      await withLoading(async () => {
        addOutput('info', `Depositing ${amount} USDT0...`)
        const tx = await contracts.deposit(CONFIG.USDT0_L2, amount)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Deposit successful!')
        refreshStatus()
      })
    }

    const auto = async ({ args }) => {
      const useSmart = args.length > 0 && args[0].toLowerCase() === 'smart'
      await withLoading(async () => {
        addOutput('info', `Auto-depositing${useSmart ? ' (smart allocation)' : ''}...`)
        const tx = await contracts.depositAvailable(CONFIG.USDT0_L2, useSmart)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Auto-deposit completed!')
        refreshStatus()
      })
    }

    const harvest = async ({ args }) => {
      const percent = args.length > 0 ? parseInt(args[0]) : 50
      if (Number.isNaN(percent) || percent < 0 || percent > 100) {
        addOutput('error', 'Invalid compound percentage (0-100)')
        return
      }
      await withLoading(async () => {
        addOutput('info', `Harvesting yield (${percent}% compound)...`)
        const tx = await contracts.harvestAndBridge(CONFIG.USDT0_L2, percent, 0, 0)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Harvest complete! Bridge to L1 initiated.')
        refreshStatus()
      })
    }

    const updateYield = async () => {
      await withLoading(async () => {
        addOutput('info', 'Updating yield data...')
        const tx = await contracts.updateYield(CONFIG.USDT0_L2)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        const yieldAmount = await contracts.getYieldAvailable()
        addOutput('success', `Yield updated: ${parseFloat(yieldAmount).toFixed(2)} USDT0`)
        refreshStatus()
      })
    }

    const compound = async ({ args }) => {
      const threshold = args.length > 0 ? parseFloat(args[0]) : 0
      if (Number.isNaN(threshold) || threshold < 0) {
        addOutput('error', 'Invalid threshold amount')
        return
      }
      await withLoading(async () => {
        addOutput('info', `Compounding${threshold > 0 ? ` (min: ${threshold})` : ''}...`)
        const tx = await contracts.momoCompound(CONFIG.USDT0_L2, threshold)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Compound successful!')
        refreshStatus()
      })
    }

    const depositL1 = async ({ args }) => {
      const amount = parseAmount(args, 'deposit-l1')
      if (!amount) return
      await withLoading(async () => {
        addOutput('info', `Depositing ${amount} USDT from L1 to L2...`)
        const signer = contracts.l1Depositor.signer
        if (!signer) {
          addOutput('error', 'Signer not available. Switch to Ethereum mainnet.')
          return
        }
        const address = await signer.getAddress()
        const amountWei = ethers.utils.parseUnits(amount.toString(), CONFIG.USDT_DECIMALS)
        const allowance = await contracts.usdtL1.allowance(address, CONFIG.L1_DEPOSITOR)
        if (allowance.lt(amountWei)) {
          addOutput('info', 'Approving USDT...')
          const approveTx = await contracts.usdtL1.approve(CONFIG.L1_DEPOSITOR, amountWei)
          await approveTx.wait()
          addOutput('success', 'Approval successful')
        }
        const tx = await contracts.depositToL2(CONFIG.USDT_L1, amount, 0)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Deposit sent! Bridge will complete in a few minutes.')
      })
    }

    const withdrawYield = async () => {
      await withLoading(async () => {
        const signer = contracts.l1Depositor.signer
        if (!signer) {
          addOutput('error', 'Signer not available. Switch to Ethereum mainnet.')
          return
        }
        const address = await signer.getAddress()
        addOutput('info', `Withdrawing yield to ${address}...`)
        const tx = await contracts.withdrawYield(CONFIG.USDT_L1, address)
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Yield withdrawn to treasury wallet!')
        refreshStatus()
      })
    }

    const checkOp = async () => {
      const result = await contracts.canPerformOp()
      if (result.canOperate) {
        addOutput('success', 'Operations are allowed')
      } else {
        addOutput('error', `Operations blocked: ${result.reason}`)
      }
    }

    const bestStrategy = async () => {
      const result = await contracts.getBestStrategy()
      if (!result) {
        addOutput('error', 'Unable to fetch best strategy')
        return
      }
      addOutput('success', `Best Strategy ID: ${result.strategyId}`)
      addOutput('success', `APY: ${result.apyBps.toFixed(2)}%`)
    }

    const aToken = async () => {
      const aTokenAddress = await contracts.getATokenAddress()
      if (aTokenAddress) {
        addOutput('success', `aToken: ${aTokenAddress}`)
      } else {
        addOutput('error', 'Unable to fetch aToken address')
      }
    }

    const bridgeFee = async ({ args }) => {
      const amount = parseAmount(args, 'bridge-fee')
      if (!amount) return
      const fee = await contracts.estimateBridgeFee(CONFIG.USDT0_L2, amount)
      addOutput('success', `Estimated bridge fee: ${parseFloat(fee).toFixed(6)} ETH`)
    }

    const tvl = async () => {
      const total = await contracts.getTotalValueLocked()
      addOutput('success', `Total Value Locked: ${parseFloat(total).toFixed(2)} USDT0`)
    }

    const showConfig = async () => {
      const config = await contracts.getVaultConfig()
      if (!config) {
        addOutput('error', 'Unable to fetch config')
        return
      }
      addOutput('info', `Min Gas Balance: ${parseFloat(config.minGas).toFixed(6)} ETH`)
      addOutput('info', `Default Slippage: ${config.slippage.toFixed(2)}%`)
      addOutput('info', `Auto Gas Refill: ${config.autoRefill.toFixed(2)}%`)
      addOutput('info', `Paused: ${config.paused ? 'YES' : 'NO'}`)
      addOutput('info', `Emergency Mode: ${config.emsMode ? 'ACTIVE' : 'INACTIVE'}`)
      addOutput('info', `Circuit Breaker: ${config.breaker ? 'ACTIVE' : 'INACTIVE'}`)
    }

    const pause = async () => {
      await withLoading(async () => {
        addOutput('warning', 'Pausing vault...')
        const tx = await contracts.pause()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('warning', 'Vault paused')
        refreshStatus()
      })
    }

    const unpause = async () => {
      await withLoading(async () => {
        addOutput('info', 'Unpausing vault...')
        const tx = await contracts.unpause()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Vault unpaused')
        refreshStatus()
      })
    }

    const emsOn = async () => {
      await withLoading(async () => {
        addOutput('warning', 'Activating emergency mode...')
        const tx = await contracts.activateEmsMode()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('warning', 'Emergency mode activated')
        refreshStatus()
      })
    }

    const emsOff = async () => {
      await withLoading(async () => {
        addOutput('info', 'Deactivating emergency mode...')
        const tx = await contracts.deactivateEmsMode()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Emergency mode deactivated')
        refreshStatus()
      })
    }

    const breakerOn = async () => {
      await withLoading(async () => {
        addOutput('warning', 'Activating circuit breaker...')
        const tx = await contracts.activateBreaker()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('warning', 'Circuit breaker activated')
        refreshStatus()
      })
    }

    const breakerOff = async () => {
      await withLoading(async () => {
        addOutput('info', 'Deactivating circuit breaker...')
        const tx = await contracts.deactivateBreaker()
        addOutput('info', `Transaction sent: ${tx.hash}`)
        await tx.wait()
        addOutput('success', 'Circuit breaker deactivated')
        refreshStatus()
      })
    }

    // Testing commands
    const testYield = async () => {
      addOutput('info', '=== Testing Yield Accumulation ===')
      
      addOutput('info', 'Step 1: Checking current status...')
      const statusBefore = await contracts.getVaultStatus()
      if (!statusBefore) {
        addOutput('error', 'Cannot get vault status. Check network.')
        return
      }
      
      addOutput('success', `Deposited: ${parseFloat(statusBefore.deposited).toFixed(2)} USDT0`)
      addOutput('success', `Current Yield: ${parseFloat(statusBefore.yieldAmount).toFixed(2)} USDT0`)
      
      addOutput('info', 'Step 2: Updating yield information...')
      await withLoading(async () => {
        const tx = await contracts.updateYield(CONFIG.USDT0_L2)
        await tx.wait()
      })
      
      const statusAfter = await contracts.getVaultStatus()
      addOutput('success', `Yield after update: ${parseFloat(statusAfter.yieldAmount).toFixed(2)} USDT0`)
      
      addOutput('info', 'Step 3: Getting current APY...')
      const apy = await contracts.getCurrentAPY()
      addOutput('success', `Current APY: ${apy.toFixed(2)}%`)
      
      addOutput('info', 'Step 4: Getting aToken address...')
      const aToken = await contracts.getATokenAddress()
      if (aToken) {
        addOutput('success', `aToken: ${aToken}`)
      }
      
      addOutput('success', '✅ Yield test completed!')
    }

    const testHarvest = async ({ args }) => {
      const compoundPercent = args.length > 0 ? parseInt(args[0]) : 50
      if (isNaN(compoundPercent) || compoundPercent < 0 || compoundPercent > 100) {
        addOutput('error', 'Invalid compound percentage (0-100)')
        return
      }

      addOutput('info', `=== Testing Harvest (${compoundPercent}% compound) ===`)
      
      addOutput('info', 'Step 1: Checking yield before harvest...')
      const statusBefore = await contracts.getVaultStatus()
      if (!statusBefore) {
        addOutput('error', 'Cannot get vault status')
        return
      }
      
      const yieldBefore = parseFloat(statusBefore.yieldAmount)
      const depositedBefore = parseFloat(statusBefore.deposited)
      
      if (yieldBefore < 1) {
        addOutput('warning', `Low yield: ${yieldBefore.toFixed(2)} USDT0. Harvest may fail.`)
        addOutput('info', 'Consider waiting for more yield or depositing more funds.')
        return
      }
      
      addOutput('success', `Yield before: ${yieldBefore.toFixed(2)} USDT0`)
      addOutput('success', `Deposited before: ${depositedBefore.toFixed(2)} USDT0`)
      
      addOutput('info', `Step 2: Harvesting (${compoundPercent}% compound)...`)
      await withLoading(async () => {
        const tx = await contracts.harvestAndBridge(CONFIG.USDT0_L2, compoundPercent, 0, 0)
        addOutput('info', `Transaction: ${tx.hash}`)
        await tx.wait()
      })
      
      addOutput('info', 'Step 3: Checking status after harvest...')
      const statusAfter = await contracts.getVaultStatus()
      const depositedAfter = parseFloat(statusAfter.deposited)
      const yieldAfter = parseFloat(statusAfter.yieldAmount)
      
      addOutput('success', `Deposited after: ${depositedAfter.toFixed(2)} USDT0`)
      addOutput('success', `Yield after: ${yieldAfter.toFixed(2)} USDT0`)
      
      if (compoundPercent > 0) {
        const expectedIncrease = (yieldBefore * compoundPercent) / 100
        if (depositedAfter > depositedBefore) {
          addOutput('success', `✅ Compound successful! Deposited increased by ~${expectedIncrease.toFixed(2)} USDT0`)
        } else {
          addOutput('warning', '⚠️ Deposited did not increase as expected')
        }
      }
      
      addOutput('success', '✅ Harvest test completed!')
      refreshStatus()
    }

    const testCompound = async () => {
      addOutput('info', '=== Testing Auto-Compound ===')
      
      const statusBefore = await contracts.getVaultStatus()
      if (!statusBefore) {
        addOutput('error', 'Cannot get vault status')
        return
      }
      
      const yieldBefore = parseFloat(statusBefore.yieldAmount)
      const depositedBefore = parseFloat(statusBefore.deposited)
      
      addOutput('info', `Yield before: ${yieldBefore.toFixed(2)} USDT0`)
      addOutput('info', `Deposited before: ${depositedBefore.toFixed(2)} USDT0`)
      
      if (yieldBefore < 1) {
        addOutput('warning', 'Low yield. Compound may not execute.')
      }
      
      await withLoading(async () => {
        const tx = await contracts.momoCompound(CONFIG.USDT0_L2, 0)
        addOutput('info', `Transaction: ${tx.hash}`)
        await tx.wait()
      })
      
      const statusAfter = await contracts.getVaultStatus()
      const depositedAfter = parseFloat(statusAfter.deposited)
      
      addOutput('success', `Deposited after: ${depositedAfter.toFixed(2)} USDT0`)
      
      if (depositedAfter > depositedBefore) {
        addOutput('success', `✅ Compound successful! Increased by ${(depositedAfter - depositedBefore).toFixed(2)} USDT0`)
      } else {
        addOutput('warning', '⚠️ No change in deposited amount')
      }
      
      refreshStatus()
    }

    const testBridge = async () => {
      addOutput('info', '=== Testing Bridge Functionality ===')
      
      addOutput('info', 'Step 1: Estimating bridge fee for 1000 USDT0...')
      const fee = await contracts.estimateBridgeFee(CONFIG.USDT0_L2, 1000)
      addOutput('success', `Estimated fee: ${parseFloat(fee).toFixed(6)} ETH`)
      
      addOutput('info', 'Step 2: Checking available yield...')
      const status = await contracts.getVaultStatus()
      if (!status) {
        addOutput('error', 'Cannot get vault status')
        return
      }
      
      const yield = parseFloat(status.yieldAmount)
      addOutput('info', `Available yield: ${yield.toFixed(2)} USDT0`)
      
      if (yield < 10) {
        addOutput('warning', 'Low yield. Bridge test will use small amount.')
      }
      
      addOutput('info', 'Step 3: Testing bridge (harvest with 0% compound)...')
      addOutput('info', 'Note: This will bridge yield to L1. Switch to Ethereum to verify.')
      
      await withLoading(async () => {
        const tx = await contracts.harvestAndBridge(CONFIG.USDT0_L2, 0, 0, 0)
        addOutput('info', `Transaction: ${tx.hash}`)
        await tx.wait()
      })
      
      addOutput('success', '✅ Bridge test completed! Check L1 depositor for yield.')
    }

    const testSafety = async () => {
      addOutput('info', '=== Testing Safety Features ===')
      
      addOutput('info', 'Step 1: Checking current configuration...')
      const config = await contracts.getVaultConfig()
      if (!config) {
        addOutput('error', 'Cannot get config')
        return
      }
      
      addOutput('info', `Paused: ${config.paused ? 'YES' : 'NO'}`)
      addOutput('info', `Emergency Mode: ${config.emsMode ? 'ACTIVE' : 'INACTIVE'}`)
      addOutput('info', `Circuit Breaker: ${config.breaker ? 'ACTIVE' : 'INACTIVE'}`)
      
      addOutput('info', 'Step 2: Testing pause...')
      await withLoading(async () => {
        const tx = await contracts.pause()
        await tx.wait()
      })
      addOutput('success', 'Vault paused')
      
      const canOp = await contracts.canPerformOp()
      if (!canOp.canOperate) {
        addOutput('success', `✅ Pause works! Operations blocked: ${canOp.reason}`)
      }
      
      addOutput('info', 'Unpausing...')
      await withLoading(async () => {
        const tx = await contracts.unpause()
        await tx.wait()
      })
      addOutput('success', 'Vault unpaused')
      
      addOutput('info', 'Step 3: Testing emergency mode...')
      await withLoading(async () => {
        const tx = await contracts.activateEmsMode()
        await tx.wait()
      })
      addOutput('success', 'Emergency mode activated')
      
      const canOp2 = await contracts.canPerformOp()
      if (!canOp2.canOperate) {
        addOutput('success', `✅ Emergency mode works! Operations blocked: ${canOp2.reason}`)
      }
      
      await withLoading(async () => {
        const tx = await contracts.deactivateEmsMode()
        await tx.wait()
      })
      addOutput('success', 'Emergency mode deactivated')
      
      addOutput('info', 'Step 4: Testing circuit breaker...')
      await withLoading(async () => {
        const tx = await contracts.activateBreaker()
        await tx.wait()
      })
      addOutput('success', 'Circuit breaker activated')
      
      await withLoading(async () => {
        const tx = await contracts.deactivateBreaker()
        await tx.wait()
      })
      addOutput('success', 'Circuit breaker deactivated')
      
      addOutput('success', '✅ Safety features test completed!')
      refreshStatus()
    }

    const testFlow = async () => {
      addOutput('info', '=== Running Automated Test Flow ===')
      addOutput('info', 'This will test: status, yield, harvest, compound, safety')
      addOutput('info', '')
      
      addOutput('info', 'Test 1: Status Check')
      await status()
      addOutput('info', '')
      
      addOutput('info', 'Test 2: Yield Accumulation')
      await testYield()
      addOutput('info', '')
      
      addOutput('info', 'Test 3: Safety Features')
      await testSafety()
      addOutput('info', '')
      
      const statusCheck = await contracts.getVaultStatus()
      if (statusCheck && parseFloat(statusCheck.yieldAmount) > 1) {
        addOutput('info', 'Test 4: Harvest (yield available)')
        await testHarvest({ args: ['50'] })
      } else {
        addOutput('warning', 'Test 4: Skipping harvest (insufficient yield)')
      }
      
      addOutput('success', '✅ Automated test flow completed!')
    }

    return {
      status: { ...COMMAND_METADATA.status, handler: () => status() },
      balances: { ...COMMAND_METADATA.balances, handler: () => balances() },
      deposit: { ...COMMAND_METADATA.deposit, handler: (ctx) => deposit(ctx) },
      auto: { ...COMMAND_METADATA.auto, handler: (ctx) => auto(ctx) },
      harvest: { ...COMMAND_METADATA.harvest, handler: (ctx) => harvest(ctx) },
      update: { ...COMMAND_METADATA.update, handler: () => updateYield() },
      compound: { ...COMMAND_METADATA.compound, handler: (ctx) => compound(ctx) },
      'deposit-l1': { ...COMMAND_METADATA['deposit-l1'], handler: (ctx) => depositL1(ctx) },
      'withdraw-yield': { ...COMMAND_METADATA['withdraw-yield'], handler: () => withdrawYield() },
      'check-op': { ...COMMAND_METADATA['check-op'], handler: () => checkOp() },
      'best-strategy': { ...COMMAND_METADATA['best-strategy'], handler: () => bestStrategy() },
      atoken: { ...COMMAND_METADATA.atoken, handler: () => aToken() },
      'bridge-fee': { ...COMMAND_METADATA['bridge-fee'], handler: (ctx) => bridgeFee(ctx) },
      tvl: { ...COMMAND_METADATA.tvl, handler: () => tvl() },
      config: { ...COMMAND_METADATA.config, handler: () => showConfig() },
      pause: { ...COMMAND_METADATA.pause, handler: () => pause() },
      unpause: { ...COMMAND_METADATA.unpause, handler: () => unpause() },
      'ems-on': { ...COMMAND_METADATA['ems-on'], handler: () => emsOn() },
      'ems-off': { ...COMMAND_METADATA['ems-off'], handler: () => emsOff() },
      'breaker-on': { ...COMMAND_METADATA['breaker-on'], handler: () => breakerOn() },
      'breaker-off': { ...COMMAND_METADATA['breaker-off'], handler: () => breakerOff() },
      'test-flow': { ...COMMAND_METADATA['test-flow'], handler: () => testFlow() },
      'test-yield': { ...COMMAND_METADATA['test-yield'], handler: () => testYield() },
      'test-harvest': { ...COMMAND_METADATA['test-harvest'], handler: (ctx) => testHarvest(ctx) },
      'test-compound': { ...COMMAND_METADATA['test-compound'], handler: () => testCompound() },
      'test-bridge': { ...COMMAND_METADATA['test-bridge'], handler: () => testBridge() },
      'test-safety': { ...COMMAND_METADATA['test-safety'], handler: () => testSafety() },
    }
  }, [contracts, addOutput, setLoading, onStatusUpdate])
}

