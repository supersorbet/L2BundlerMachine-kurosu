// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockAToken
/// @notice Mock yield-bearing token (aToken)
contract MockAToken is ERC20 {
    address public immutable underlying;
    address public immutable pool;

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
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == pool, "Only pool");
        _burn(from, amount);
    }
}

