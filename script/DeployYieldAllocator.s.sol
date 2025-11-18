// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {YieldAllocator} from "../src/YieldAllocator.sol";
import {TydroStrategy} from "../src/strategies/TydroStrategy.sol";
import {VelodromeStrategy} from "../src/strategies/VelodromeStrategy.sol";

contract DeployYieldAllocator is Script {
    // Ink L2 addresses
    address constant TYDRO_POOL = 0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA;
    address constant L2_ENCODER = 0x988B5d3863bdEE83339Be41cD31344Dfd9FD197c;
    address constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;

    function run() external returns (
        address allocator,
        address tydroStrategy,
        address veloStrategy
    ) {
        // Handle private key with or without 0x prefix
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            // Parse as hex without 0x prefix
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying YieldAllocator System ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy strategies
        console.log("Deploying TydroStrategy...");
        TydroStrategy tydro = new TydroStrategy(TYDRO_POOL, L2_ENCODER);
        console.log("TydroStrategy deployed at:", address(tydro));

        console.log("Deploying VelodromeStrategy...");
        VelodromeStrategy velo = new VelodromeStrategy(VELO_ROUTER);
        console.log("VelodromeStrategy deployed at:", address(velo));

        // Deploy allocator
        console.log("Deploying YieldAllocator...");
        YieldAllocator alloc = new YieldAllocator();
        console.log("YieldAllocator deployed at:", address(alloc));

        // Register strategies
        console.log("Registering strategies...");
        alloc.registerStrategy(tydro);
        alloc.registerStrategy(velo);
        console.log("Strategies registered");

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("YieldAllocator:", address(alloc));
        console.log("TydroStrategy:", address(tydro));
        console.log("VelodromeStrategy:", address(velo));
        console.log("\nNext steps:");
        console.log("1. Set aux data for Velodrome pairs");
        console.log("2. Set max allocations");
        console.log("3. Integrate with vault: vault.setYieldAllocator(allocatorAddress)");

        return (address(alloc), address(tydro), address(velo));
    }
}
