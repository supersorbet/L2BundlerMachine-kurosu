import React from 'react'
import './StatusPanel.css'

export default function StatusPanel({ status, balances, network }) {
  return (
    <div className="status-panel">
      {network !== 'Ink L2' && (
        <div className="status-section">
          <h3>⚠️ Network Notice</h3>
          <div className="status-grid">
            <div className="status-item">
              <span className="status-label">Current Network:</span>
              <span className="status-value warning">{network}</span>
            </div>
            <div className="status-item">
              <span className="status-label">Required:</span>
              <span className="status-value">Ink L2 (for vault operations)</span>
            </div>
          </div>
        </div>
      )}
      <div className="status-section">
        <h3>📊 Vault Status</h3>
        <div className="status-grid">
          <div className="status-item">
            <span className="status-label">Deposited:</span>
            <span className="status-value">
              {status?.deposited ? `${parseFloat(status.deposited).toFixed(2)} USDT0` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">Current Balance:</span>
            <span className="status-value">
              {status?.current ? `${parseFloat(status.current).toFixed(2)} USDT0` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">Yield Available:</span>
            <span className="status-value yield">
              {status?.yieldAmount ? `${parseFloat(status.yieldAmount).toFixed(2)} USDT0` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">Gas Balance:</span>
            <span className="status-value">
              {status?.gas ? `${parseFloat(status.gas).toFixed(6)} ETH` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">APY:</span>
            <span className="status-value">
              {status?.apy ? `${status.apy.toFixed(2)}%` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">Health:</span>
            <span className={`status-value ${status?.health?.isHealthy ? 'success' : 'error'}`}>
              {status?.health ? (status.health.isHealthy ? 'Healthy' : 'Unhealthy') : '-'}
            </span>
          </div>
        </div>
      </div>
      
      <div className="status-section">
        <h3>💰 Balances</h3>
        <div className="status-grid">
          <div className="status-item">
            <span className="status-label">L1 USDT:</span>
            <span className="status-value">
              {balances?.l1USDT ? `${parseFloat(balances.l1USDT).toFixed(2)} USDT` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">L2 USDT0:</span>
            <span className="status-value">
              {balances?.l2USDT0 ? `${parseFloat(balances.l2USDT0).toFixed(2)} USDT0` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">L1 ETH:</span>
            <span className="status-value">
              {balances?.l1ETH ? `${parseFloat(balances.l1ETH).toFixed(6)} ETH` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">L2 ETH:</span>
            <span className="status-value">
              {balances?.l2ETH ? `${parseFloat(balances.l2ETH).toFixed(6)} ETH` : '-'}
            </span>
          </div>
          <div className="status-item">
            <span className="status-label">Vault USDT0:</span>
            <span className="status-value">
              {balances?.vaultUSDT0 ? `${parseFloat(balances.vaultUSDT0).toFixed(2)} USDT0` : '-'}
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}

