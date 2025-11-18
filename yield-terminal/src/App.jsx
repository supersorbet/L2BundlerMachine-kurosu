import React, { useState, useEffect, useRef } from 'react'
import { ethers } from 'ethers'
import './App.css'
import { CONFIG, ABIS } from './config'
import Terminal from './components/Terminal'
import StatusPanel from './components/StatusPanel'
import { useWallet } from './hooks/useWallet'
import { useContracts } from './hooks/useContracts'

function App() {
  const { provider, signer, address, connect, disconnect, isConnected, network } = useWallet()
  const contracts = useContracts(provider, signer)
  const [status, setStatus] = useState(null)
  const [balances, setBalances] = useState({})
  const [loading, setLoading] = useState(false)

  // Update status periodically
  useEffect(() => {
    if (!isConnected || !contracts) return

    const updateStatus = async () => {
      try {
        // Only update if on Ink L2 network
        if (network !== 'Ink L2') {
          return // Skip updates if not on correct network
        }
        
        const vaultStatus = await contracts.getVaultStatus()
        const health = await contracts.getVaultHealth()
        const apy = await contracts.getCurrentAPY()
        
        if (vaultStatus) {
          setStatus({
            ...vaultStatus,
            health,
            apy
          })
        }
      } catch (error) {
        // Silently handle network mismatches
        if (error.data === '0x') return
        console.error('Error updating status:', error)
      }
    }

    updateStatus()
    const interval = setInterval(updateStatus, 10000) // Update every 10 seconds
    return () => clearInterval(interval)
  }, [isConnected, contracts, network])

  // Update balances periodically
  useEffect(() => {
    if (!isConnected || !contracts || !address) return

    const updateBalances = async () => {
      try {
        const currentNetwork = network
        
        // Get ETH balance (works on any network)
        const ethBalance = await contracts.getETHBalance(address)
        
        // Get token balances based on network
        if (currentNetwork === 'Ethereum') {
          // On L1, get L1 balances
          const l1USDT = await contracts.getBalance(CONFIG.USDT_L1, address)
          setBalances({
            l1ETH: ethBalance,
            l2ETH: '0',
            l1USDT,
            l2USDT0: '0',
            vaultUSDT0: '0'
          })
        } else if (currentNetwork === 'Ink L2') {
          // On L2, get L2 balances
          const l2USDT0 = await contracts.getBalance(CONFIG.USDT0_L2, address)
          const vaultUSDT0 = await contracts.getBalance(CONFIG.USDT0_L2, CONFIG.L2_VAULT)
          setBalances({
            l1ETH: '0',
            l2ETH: ethBalance,
            l1USDT: '0',
            l2USDT0,
            vaultUSDT0
          })
        }
      } catch (error) {
        // Silently handle network mismatches
        if (error.data === '0x') return
        console.error('Error updating balances:', error)
      }
    }

    updateBalances()
    const interval = setInterval(updateBalances, 10000)
    return () => clearInterval(interval)
  }, [isConnected, contracts, address, network])

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-left">
          <span className="terminal-icon">⚡</span>
          <span className="terminal-title">Yield Terminal</span>
        </div>
        <div className="header-right">
          {isConnected ? (
            <>
              <button className="btn-connect connected" onClick={disconnect}>
                Disconnect
              </button>
              <span className="wallet-address">{address?.slice(0, 6)}...{address?.slice(-4)}</span>
              <span className="network-badge connected">{network}</span>
            </>
          ) : (
            <>
              <button className="btn-connect" onClick={connect}>
                Connect Wallet
              </button>
              <span className="network-badge">Disconnected</span>
            </>
          )}
        </div>
      </header>

      {isConnected && network !== 'Ink L2' && network !== 'Ethereum' && (
        <div className="network-warning">
          ⚠️ Connected to unsupported network: {network}. Please switch to Ethereum or Ink L2.
        </div>
      )}

      <div className="app-content">
        <Terminal 
          contracts={contracts}
          isConnected={isConnected}
          network={network}
          loading={loading}
          setLoading={setLoading}
          onStatusUpdate={() => {
            // Trigger status update
            if (contracts && network === 'Ink L2') {
              contracts.getVaultStatus().then(setStatus)
            }
          }}
        />
        <StatusPanel status={status} balances={balances} network={network} />
      </div>

      {loading && (
        <div className="loading-overlay">
          <div className="spinner"></div>
          <div className="loading-text">Processing transaction...</div>
        </div>
      )}
    </div>
  )
}

export default App

