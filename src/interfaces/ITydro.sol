// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITydroPool {
    function deposit(address token, uint256 amount) external returns (uint256 shares);
    function withdraw(address token, uint256 shares) external returns (uint256 amount);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

