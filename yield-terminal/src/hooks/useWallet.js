import { useState, useEffect } from 'react'
import { ethers } from 'ethers'
import { CONFIG } from '../config'

export function useWallet() {
  const [provider, setProvider] = useState(null)
  const [signer, setSigner] = useState(null)
  const [address, setAddress] = useState(null)
  const [isConnected, setIsConnected] = useState(false)
  const [network, setNetwork] = useState('Disconnected')

  useEffect(() => {
    if (typeof window.ethereum === 'undefined') {
      return
    }

    // Check if already connected
    const checkConnection = async () => {
      try {
        const accounts = await window.ethereum.request({ method: 'eth_accounts' })
        if (accounts.length > 0) {
          await connect()
        }
      } catch (error) {
        console.error('Error checking connection:', error)
      }
    }

    checkConnection()

    // Listen for account changes
    window.ethereum.on('accountsChanged', (accounts) => {
      if (accounts.length === 0) {
        disconnect()
      } else {
        connect()
      }
    })

    // Listen for network changes
    window.ethereum.on('chainChanged', () => {
      window.location.reload()
    })
  }, [])

  const connect = async () => {
    try {
      if (typeof window.ethereum === 'undefined') {
        throw new Error('MetaMask is not installed')
      }

      const provider = new ethers.providers.Web3Provider(window.ethereum)
      await provider.send("eth_requestAccounts", [])
      const signer = provider.getSigner()
      const address = await signer.getAddress()
      const networkData = await provider.getNetwork()

      let networkName = 'Unknown'
      if (networkData.chainId === CONFIG.ETH_CHAIN_ID) {
        networkName = 'Ethereum'
      } else if (networkData.chainId === CONFIG.INK_CHAIN_ID) {
        networkName = 'Ink L2'
      }

      setProvider(provider)
      setSigner(signer)
      setAddress(address)
      setIsConnected(true)
      setNetwork(networkName)
    } catch (error) {
      console.error('Connection error:', error)
      throw error
    }
  }

  const disconnect = () => {
    setProvider(null)
    setSigner(null)
    setAddress(null)
    setIsConnected(false)
    setNetwork('Disconnected')
  }

  return {
    provider,
    signer,
    address,
    isConnected,
    network,
    connect,
    disconnect
  }
}

