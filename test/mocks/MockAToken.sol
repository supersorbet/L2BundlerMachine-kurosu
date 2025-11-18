// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockAToken
/// @notice Mock yield-bearing token (aToken)
contract MockAToken is ERC20 {
    address public immutable underlying;
    address public immutable pool;

    // Simulate 3% APY accrual on aToken balance
    uint256 private constant ANNUAL_YIELD_BPS = 300; // 3%
    mapping(address => uint256) private lastUpdate;

    constructor(address _underlying, address _pool) ERC20("Mock aToken", "MaTOKEN") {
        underlying = _underlying;
        pool = _pool;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == pool, "Only pool");
        _mint(to, amount);
        lastUpdate[to] = block.timestamp;
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == pool, "Only pool");
        _burn(from, amount);
        lastUpdate[from] = block.timestamp;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 base = super.balanceOf(account);
        if (base == 0) return 0;
        uint256 elapsed = block.timestamp - lastUpdate[account];
        if (elapsed == 0) return base;
        uint256 accrued = (base * ANNUAL_YIELD_BPS * elapsed) / (10000 * 365 days);
        return base + accrued;
    }

    function rawBalanceOf(address account) external view returns (uint256) {
        return super.balanceOf(account);
    }
}

