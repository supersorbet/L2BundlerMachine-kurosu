// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {VelodromeUtils} from "../src/utils/VelodromeUtils.sol";
import {VelodromeViewer} from "../src/utils/VelodromeViewer.sol";

contract DeployVelodromeUtils is Script {
    address constant VELO_ROUTER = 0x01D40099fCD87C018969B0e8D4aB1633Fb34763C;
    address constant VELO_VOTER = 0x41c914EE0c7e1A30ed2aDAe2F3d8A3c6a1B8eE8f;
    
    function run() external {
        string memory privateKeyStr = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        bytes memory keyBytes = bytes(privateKeyStr);
        if (keyBytes.length > 2 && keyBytes[0] == '0' && keyBytes[1] == 'x') {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = vm.parseUint(string.concat("0x", privateKeyStr));
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        VelodromeUtils utils = new VelodromeUtils(VELO_ROUTER, VELO_VOTER);
        console.log("VelodromeUtils deployed at:", address(utils));
        
        VelodromeViewer viewer = new VelodromeViewer(VELO_ROUTER, VELO_VOTER);
        console.log("VelodromeViewer deployed at:", address(viewer));
        
        vm.stopBroadcast();
        
        console.log("\n=== Usage ===");
        console.log("1. Approve tokens to VelodromeUtils");
        console.log("2. Call createLP() or zapIntoLP() from your EOA");
        console.log("3. LP tokens will be sent to your EOA");
        console.log("4. Connect your EOA to Velodrome UI to see positions!");
        console.log("\nViewer contract for checking balances:");
        console.log("  getLPInfo(yourEOA, tokenA, tokenB, stable)");
    }
}

