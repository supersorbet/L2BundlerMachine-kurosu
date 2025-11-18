import { useMemo } from 'react'
import { ethers } from 'ethers'
import { CONFIG, ABIS } from '../config'

export function useContracts(provider, signer) {
  return useMemo(() => {
    if (!provider) return null

    const contracts = {
      l2Vault: new ethers.Contract(CONFIG.L2_VAULT, ABIS.L2_VAULT, signer || provider),
      l1Depositor: new ethers.Contract(CONFIG.L1_DEPOSITOR, ABIS.L1_DEPOSITOR, signer || provider),
      usdtL1: new ethers.Contract(CONFIG.USDT_L1, ABIS.ERC20, signer || provider),
      usdt0L2: new ethers.Contract(CONFIG.USDT0_L2, ABIS.ERC20, signer || provider),
    }

    return {
      ...contracts,
      
      async getVaultStatus(token = CONFIG.USDT0_L2) {
        try {
          // Check network first
          const network = await provider.getNetwork()
          if (network.chainId !== CONFIG.INK_CHAIN_ID) {
            return null // Wrong network, silently return null
          }
          
          const status = await contracts.l2Vault.getStatus(token)
          return {
            deposited: ethers.utils.formatUnits(status.depositedAmount, CONFIG.USDT_DECIMALS),
            current: ethers.utils.formatUnits(status.currentBalance, CONFIG.USDT_DECIMALS),
            yieldAmount: ethers.utils.formatUnits(status.yieldAvailable, CONFIG.USDT_DECIMALS),
            gas: ethers.utils.formatEther(status.gasBalance),
          }
        } catch (error) {
          // Only log if it's not a network mismatch
          if (error.data && error.data !== '0x') {
            console.error('Error getting vault status:', error)
          }
          return null
        }
      },

      async getYieldAvailable(token = CONFIG.USDT0_L2) {
        try {
          const yieldAmount = await contracts.l2Vault.getYieldAvailable(token)
          return ethers.utils.formatUnits(yieldAmount, CONFIG.USDT_DECIMALS)
        } catch (error) {
          console.error('Error getting yield:', error)
          return "0"
        }
      },

      async getCurrentAPY(token = CONFIG.USDT0_L2) {
        try {
          const network = await provider.getNetwork()
          if (network.chainId !== CONFIG.INK_CHAIN_ID) {
            return 0 // Wrong network
          }
          
          const apy = await contracts.l2Vault.getCurrentAPY(token)
          const apyBps = apy.div(ethers.BigNumber.from(100))
          return apyBps.toNumber() / 100
        } catch (error) {
          if (error.data && error.data !== '0x') {
            console.error('Error getting APY:', error)
          }
          return 0
        }
      },

      async getVaultHealth(token = CONFIG.USDT0_L2) {
        try {
          const network = await provider.getNetwork()
          if (network.chainId !== CONFIG.INK_CHAIN_ID) {
            return null // Wrong network
          }
          
          const health = await contracts.l2Vault.getVaultHealth(token)
          return {
            isHealthy: health.isHealthy,
            hasGas: health.hasGas,
            hasYield: health.hasYield,
            timeSinceUpdate: health.timeSinceLastUpdate.toNumber(),
            totalValue: ethers.utils.formatUnits(health.totalValueLocked, CONFIG.USDT_DECIMALS),
          }
        } catch (error) {
          if (error.data && error.data !== '0x') {
            console.error('Error getting vault health:', error)
          }
          return null
        }
      },

      async getBalance(token, address) {
        try {
          const contract = new ethers.Contract(token, ABIS.ERC20, provider)
          const balance = await contract.balanceOf(address)
          const decimals = await contract.decimals().catch(() => CONFIG.ETH_DECIMALS)
          return ethers.utils.formatUnits(balance, decimals)
        } catch (error) {
          // Only log if it's not a network mismatch (empty data means contract doesn't exist)
          if (error.data && error.data !== '0x') {
            console.error('Error getting balance:', error)
          }
          return "0"
        }
      },

      async getETHBalance(address) {
        try {
          const balance = await provider.getBalance(address)
          return ethers.utils.formatEther(balance)
        } catch (error) {
          console.error('Error getting ETH balance:', error)
          return "0"
        }
      },

      // Write operations
      async deposit(token, amount) {
        if (!signer) throw new Error('Wallet not connected')
        const amountWei = ethers.utils.parseUnits(amount.toString(), CONFIG.USDT_DECIMALS)
        return await contracts.l2Vault.deposit(token, amountWei)
      },

      async depositAvailable(token, useSmartAllocation = false) {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.depositAvailable(token, useSmartAllocation)
      },

      async harvestAndBridge(token, compoundPercent, customSlippageBps = 0, minBridgeAmount = 0) {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.harvestAndBridge(
          token,
          compoundPercent,
          customSlippageBps,
          minBridgeAmount
        )
      },

      async updateYield(token) {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.updateYield(token)
      },

      async momoCompound(token, minYieldThreshold) {
        if (!signer) throw new Error('Wallet not connected')
        const thresholdWei = ethers.utils.parseUnits(minYieldThreshold.toString(), CONFIG.USDT_DECIMALS)
        return await contracts.l2Vault.momoCompound(token, thresholdWei)
      },

      async depositToL2(token, amount, minAmount = 0) {
        if (!signer) throw new Error('Wallet not connected')
        const amountWei = ethers.utils.parseUnits(amount.toString(), CONFIG.USDT_DECIMALS)
        const minAmountWei = ethers.utils.parseUnits(minAmount.toString(), CONFIG.USDT_DECIMALS)
        return await contracts.l1Depositor.depositToL2(token, amountWei, minAmountWei)
      },

      async withdrawYield(token, to) {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l1Depositor.withdrawYield(token, to)
      },

      // Additional view functions for testing
      async canPerformOp(token = CONFIG.USDT0_L2) {
        try {
          const result = await contracts.l2Vault.canPerformOp(token)
          return {
            canOperate: result.canOperate,
            reason: result.reason
          }
        } catch (error) {
          console.error('Error checking operation:', error)
          return { canOperate: false, reason: 'Error checking' }
        }
      },

      async getBestStrategy(token = CONFIG.USDT0_L2) {
        try {
          const result = await contracts.l2Vault.getBestStrategy(token)
          return {
            strategyId: result.strategyId,
            apyBps: result.apyBps.toNumber() / 100
          }
        } catch (error) {
          console.error('Error getting best strategy:', error)
          return null
        }
      },

      async getATokenAddress(token = CONFIG.USDT0_L2) {
        try {
          return await contracts.l2Vault.getATokenAddress(token)
        } catch (error) {
          console.error('Error getting aToken address:', error)
          return null
        }
      },

      async estimateBridgeFee(token, amount) {
        try {
          const amountWei = ethers.utils.parseUnits(amount.toString(), CONFIG.USDT_DECIMALS)
          const fee = await contracts.l2Vault.estimateBridgeFee(token, amountWei)
          return ethers.utils.formatEther(fee)
        } catch (error) {
          console.error('Error estimating bridge fee:', error)
          return "0"
        }
      },

      async getTotalValueLocked(tokens = [CONFIG.USDT0_L2]) {
        try {
          const total = await contracts.l2Vault.getTotalValueLocked(tokens)
          return ethers.utils.formatUnits(total, CONFIG.USDT_DECIMALS)
        } catch (error) {
          console.error('Error getting TVL:', error)
          return "0"
        }
      },

      async getVaultConfig() {
        try {
          const [minGas, slippage, autoRefill, paused, emsMode, breaker] = await Promise.all([
            contracts.l2Vault.minGasBalance(),
            contracts.l2Vault.defaultSlippageBps(),
            contracts.l2Vault.autoGasRefillBps(),
            contracts.l2Vault.paused(),
            contracts.l2Vault.emergencyMode(),
            contracts.l2Vault.breakerActive()
          ])
          return {
            minGas: ethers.utils.formatEther(minGas),
            slippage: slippage.toNumber() / 100,
            autoRefill: autoRefill.toNumber() / 100,
            paused,
            emsMode,
            breaker
          }
        } catch (error) {
          console.error('Error getting config:', error)
          return null
        }
      },

      // Admin functions
      async pause() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.pause()
      },

      async unpause() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.unpause()
      },

      async activateEmsMode() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.activateEmsMode()
      },

      async deactivateEmsMode() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.deactivateEmsMode()
      },

      async activateBreaker() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.activateBreaker()
      },

      async deactivateBreaker() {
        if (!signer) throw new Error('Wallet not connected')
        return await contracts.l2Vault.deactivateBreaker()
      },
    }
  }, [provider, signer])
}

