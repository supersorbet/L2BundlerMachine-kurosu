# Yield Terminal - NPM UI

A modern React-based terminal-style UI for managing your L1-L2 yield system.

## Quick Start

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

The app will open at `http://localhost:3000`

## Configuration

Update contract addresses in `src/config.js`:

```javascript
export const CONFIG = {
  L2_VAULT: "0x...",           // Your L2 vault address
  L1_DEPOSITOR: "0x...",      // Your L1 depositor address
  USDT_L1: "0x...",           // USDT on Ethereum
  USDT0_L2: "0x...",          // USDT0 on Ink L2
  // ...
}
```

## Features

- ✅ React + Vite for fast development
- ✅ Terminal-style command interface
- ✅ MetaMask wallet integration
- ✅ Real-time status updates
- ✅ Live balance monitoring
- ✅ Transaction tracking

## Commands

- `help` - Show available commands
- `status` - Show vault status
- `balances` - Show all balances
- `deposit <amount>` - Deposit to Tydro
- `auto [smart]` - Auto-deposit available funds
- `harvest [%]` - Harvest yield and bridge
- `update` - Update yield info
- `compound [threshold]` - Compound yield
- `deposit-l1 <amount>` - Deposit from L1 to L2
- `withdraw-yield` - Withdraw yield from L1
- `clear` - Clear terminal

## Development

Built with:
- React 18
- Vite 5
- Ethers.js 5.7
- Modern ES6+ JavaScript

## License

MIT

