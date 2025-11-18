export const COMMAND_LIST = [
  { name: 'status', usage: 'status', description: 'Show vault status', category: 'Monitoring', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'balances', usage: 'balances', description: 'Show wallet & vault balances', category: 'Monitoring', requiresConnection: true },
  { name: 'deposit', usage: 'deposit <amount>', description: 'Deposit USDT0 to Tydro', category: 'Operations', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'auto', usage: 'auto [smart]', description: 'Auto-deposit available funds', category: 'Operations', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'harvest', usage: 'harvest [compound%]', description: 'Harvest yield and bridge to L1', category: 'Operations', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'update', usage: 'update', description: 'Update yield information', category: 'Operations', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'compound', usage: 'compound [minYield]', description: 'Compound available yield', category: 'Operations', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'deposit-l1', usage: 'deposit-l1 <amount>', description: 'Deposit USDT from L1 to L2', category: 'Bridge', requiresConnection: true, requiresNetwork: 'Ethereum' },
  { name: 'withdraw-yield', usage: 'withdraw-yield', description: 'Withdraw yield on L1', category: 'Bridge', requiresConnection: true, requiresNetwork: 'Ethereum' },
  { name: 'check-op', usage: 'check-op', description: 'Check if operations are allowed', category: 'Safety', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'best-strategy', usage: 'best-strategy', description: 'Get best yield strategy', category: 'Analytics', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'atoken', usage: 'atoken', description: 'Show current aToken address', category: 'Analytics', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'bridge-fee', usage: 'bridge-fee <amount>', description: 'Estimate bridge fee in ETH', category: 'Analytics', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'tvl', usage: 'tvl', description: 'Show total value locked', category: 'Analytics', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'config', usage: 'config', description: 'Show vault configuration', category: 'Safety', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'pause', usage: 'pause', description: 'Pause the vault (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'unpause', usage: 'unpause', description: 'Unpause the vault (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'ems-on', usage: 'ems-on', description: 'Activate emergency mode (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'ems-off', usage: 'ems-off', description: 'Deactivate emergency mode (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'breaker-on', usage: 'breaker-on', description: 'Activate circuit breaker (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'breaker-off', usage: 'breaker-off', description: 'Deactivate circuit breaker (owner only)', category: 'Admin', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-flow', usage: 'test-flow', description: 'Run automated test flow', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-yield', usage: 'test-yield', description: 'Test yield accumulation', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-harvest', usage: 'test-harvest [compound%]', description: 'Test harvest functionality', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-compound', usage: 'test-compound', description: 'Test compound functionality', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-bridge', usage: 'test-bridge', description: 'Test bridge functionality', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'test-safety', usage: 'test-safety', description: 'Test safety features (pause/ems/breaker)', category: 'Testing', requiresConnection: true, requiresNetwork: 'Ink L2' },
  { name: 'help', usage: 'help', description: 'Show available commands', category: 'Utility', requiresConnection: false },
  { name: 'clear', usage: 'clear', description: 'Clear terminal output', category: 'Utility', requiresConnection: false },
]

export const COMMAND_METADATA = COMMAND_LIST.reduce((acc, command) => {
  acc[command.name] = command
  return acc
}, {})

