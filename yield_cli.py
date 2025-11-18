#!/usr/bin/env python3
"""
Yield Management CLI Tool
"""

import subprocess
import json
import sys
import os
from decimal import Decimal
import time

# Configuration
L1_DEPOSITOR = "0xaA1be5133e5dBC9AA5539D29C939DCbb8FD5B110"
L2_VAULT = "0xB4BF6a67c329A2Fd27f224F11aB24e6963B89fb7"
USDT_L1 = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
USDT0_L2 = "0x0200C29006150606B650577BBE7B6248F58470c1"
INK_RPC = "https://rpc-gel.inkonchain.com"
ETH_RPC = "https://eth.llamarpc.com"

def run_cast(cmd):
    """Run cast command and return result"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=os.getcwd())
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            print(f"❌ Error: {result.stderr}")
            return None
    except Exception as e:
        print(f"❌ Exception: {e}")
        return None

def load_env():
    """Load environment variables"""
    try:
        with open('.env', 'r') as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
    except FileNotFoundError:
        print("❌ .env file not found")
        sys.exit(1)

    return os.environ.get('PRIVATE_KEY')

def get_wallet_address():
    """Get wallet address from private key"""
    private_key = load_env()
    if not private_key:
        print("❌ PRIVATE_KEY not found in .env")
        sys.exit(1)

    cmd = f"cast wallet address {private_key}"
    return run_cast(cmd)

def check_balances():
    """Check all balances"""
    print("=== Balance Check ===")

    wallet = get_wallet_address()
    print(f"Wallet: {wallet}")
    print()

    # L1 Balances
    print("L1 (Ethereum):")
    eth_l1 = run_cast(f"cast balance {wallet} --rpc-url {ETH_RPC}")
    if eth_l1:
        print(".6f")

    usdt_l1 = run_cast(f"cast call {USDT_L1} 'balanceOf(address)' {wallet} --rpc-url {ETH_RPC}")
    if usdt_l1:
        usdt_decimals = int(usdt_l1, 16) / 10**6
        print(".2f")

    # L2 Balances
    print("L2 (Ink):")
    eth_l2 = run_cast(f"cast balance {wallet} --rpc-url {INK_RPC}")
    if eth_l2:
        print(".6f")

    usdt0_l2 = run_cast(f"cast call {USDT0_L2} 'balanceOf(address)' {wallet} --rpc-url {INK_RPC}")
    if usdt0_l2:
        usdt0_decimals = int(usdt0_l2, 16) / 10**6
        print(".2f")

    # Vault balances
    print("L2 Vault:")
    vault_usdt0 = run_cast(f"cast call {USDT0_L2} 'balanceOf(address)' {L2_VAULT} --rpc-url {INK_RPC}")
    if vault_usdt0:
        vault_decimals = int(vault_usdt0, 16) / 10**6
        print(".2f")

    # Vault status
    print("Vault Status:")
    status = run_cast(f"cast call {L2_VAULT} 'getStatus(address)' {USDT0_L2} --rpc-url {INK_RPC}")
    if status:
        parts = status.split()
        if len(parts) >= 4:
            deposited = int(parts[0], 16) / 10**6
            current = int(parts[1], 16) / 10**6
            yield_amt = int(parts[2], 16) / 10**6
            gas_balance = int(parts[3], 16) / 10**18
            print(".2f")
            print(".2f")
            print(".2f")
            print(".6f")

def deposit_l1_to_l2(amount_usdt):
    """Deposit USDT from L1 to L2"""
    print(f"=== Depositing ${amount_usdt} USDT L1 → L2 ===")

    private_key = load_env()
    amount_wei = int(float(amount_usdt) * 10**6)  # USDT has 6 decimals

    # Check balance
    wallet = get_wallet_address()
    balance = run_cast(f"cast call {USDT_L1} 'balanceOf(address)' {wallet} --rpc-url {ETH_RPC}")
    if balance and int(balance, 16) < amount_wei:
        print(f"❌ Insufficient USDT balance. Have {int(balance, 16) / 10**6:.2f} USDT")
        return

    print("1. Approving USDT for L1 depositor...")
    cmd = f"cast send {USDT_L1} 'approve(address,uint256)' {L1_DEPOSITOR} {amount_wei} --private-key {private_key} --rpc-url {ETH_RPC}"
    result = run_cast(cmd)
    if not result:
        return

    print("2. Depositing to L2 via Across...")
    cmd = f"cast send {L1_DEPOSITOR} 'depositToL2(address,uint256,uint256)' {USDT_L1} {amount_wei} 0 --private-key {private_key} --rpc-url {ETH_RPC}"
    result = run_cast(cmd)
    if result:
        print("✅ Deposit sent! Wait 2-3 minutes for bridge completion.")
        print("Transaction:", result)
    else:
        print("❌ Deposit failed")

def auto_deposit_l2():
    """Auto-deposit available L2 funds to Tydro"""
    print("=== Auto-Deposit L2 Funds to Tydro ===")

    private_key = load_env()

    # Check vault balance
    vault_balance = run_cast(f"cast call {USDT0_L2} 'balanceOf(address)' {L2_VAULT} --rpc-url {INK_RPC}")
    if vault_balance and int(vault_balance, 16) == 0:
        print("❌ No funds in vault to deposit")
        return

    balance_usdt = int(vault_balance, 16) / 10**6
    print(".2f")

    cmd = f"cast send {L2_VAULT} 'depositAvailable(address,bool)' {USDT0_L2} false --private-key {private_key} --rpc-url {INK_RPC}"
    result = run_cast(cmd)
    if result:
        print("✅ Auto-deposit completed!")
    else:
        print("❌ Auto-deposit failed")

def harvest_and_bridge(compound_percent=50):
    """Harvest yield and bridge back to L1"""
    print(f"=== Harvest & Bridge (Compound {compound_percent}%) ===")

    private_key = load_env()

    cmd = f"cast send {L2_VAULT} 'harvestAndBridge(address,uint8,uint64,uint256)' {USDT0_L2} {compound_percent} 0 0 --private-key {private_key} --rpc-url {INK_RPC}"
    result = run_cast(cmd)
    if result:
        print("✅ Harvest and bridge completed!")
        print("Wait 2-3 minutes for L1 bridge completion")
    else:
        print("❌ Harvest and bridge failed (likely no yield available)")

def update_yield():
    """Update yield information"""
    print("=== Updating Yield Information ===")

    private_key = load_env()

    cmd = f"cast send {L2_VAULT} 'updateYield(address)' {USDT0_L2} --private-key {private_key} --rpc-url {INK_RPC}"
    result = run_cast(cmd)
    if result:
        print("✅ Yield updated")

        # Check new yield
        yield_amt = run_cast(f"cast call {L2_VAULT} 'getYieldAvailable(address)' {USDT0_L2} --rpc-url {INK_RPC}")
        if yield_amt:
            yield_usdt = int(yield_amt, 16) / 10**6
            print(".6f")
    else:
        print("❌ Yield update failed")

def smart_operations():
    """Run smart allocation operations"""
    print("=== Smart Operations ===")

    private_key = load_env()

    # Check if allocator is set
    allocator = run_cast(f"cast call {L2_VAULT} 'yieldAllocator()' --rpc-url {INK_RPC}")
    if not allocator or allocator == "0x0000000000000000000000000000000000000000":
        print("❌ YieldAllocator not configured")
        return

    print("✅ YieldAllocator found")

    # Smart rebalance
    print("Running smart rebalance...")
    cmd = f"cast send {L2_VAULT} 'smartRebalance(address)' {USDT0_L2} --private-key {private_key} --rpc-url {INK_RPC}"
    run_cast(cmd)

    # Smart compound
    print("Running smart compound...")
    cmd = f"cast send {L2_VAULT} 'smartCompound(address)' {USDT0_L2} --private-key {private_key} --rpc-url {INK_RPC}"
    run_cast(cmd)

    print("✅ Smart operations completed")

def show_help():
    """Show help"""
    print("Yield Management CLI Tool")
    print("=" * 40)
    print()
    print("Commands:")
    print("  balances    - Check all balances")
    print("  deposit     - Deposit USDT from L1 to L2")
    print("  auto        - Auto-deposit L2 funds to Tydro")
    print("  harvest     - Harvest yield and bridge to L1")
    print("  update      - Update yield information")
    print("  smart       - Run smart allocation operations")
    print("  help        - Show this help")
    print()
    print("Usage:")
    print("  python yield_cli.py balances")
    print("  python yield_cli.py deposit 1.00")
    print("  python yield_cli.py harvest 75")
    print()

def main():
    if len(sys.argv) < 2:
        show_help()
        return

    command = sys.argv[1]

    if command == "balances":
        check_balances()
    elif command == "deposit":
        if len(sys.argv) < 3:
            print("Usage: python yield_cli.py deposit <amount_usdt>")
            return
        amount = float(sys.argv[2])
        deposit_l1_to_l2(amount)
    elif command == "auto":
        auto_deposit_l2()
    elif command == "harvest":
        compound = 50  # default
        if len(sys.argv) >= 3:
            compound = int(sys.argv[2])
        harvest_and_bridge(compound)
    elif command == "update":
        update_yield()
    elif command == "smart":
        smart_operations()
    elif command == "help":
        show_help()
    else:
        print(f"Unknown command: {command}")
        show_help()

if __name__ == "__main__":
    main()
