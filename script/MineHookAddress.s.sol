// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {RentYieldHook} from "../src/RentYieldHook.sol";

contract MineHookAddress is Script {
    function run() external {
        // 1. Define the flags your hook needs
        // Bitwise OR the permissions you set in your contract
        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        // 2. Mock PoolManager address (or use the one from your testnet)
        address poolManager = 0x...; // Replace with your local/testnet PoolManager

        // 3. Mining parameters
        // The CREATE2_DEPLOYER is standard across most chains
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        console.log("Mining salt for flags...", flags);

        // 4. Find the salt
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(RentYieldHook).creationCode,
            abi.encode(poolManager)
        );

        console.log("SUCCESS!");
        console.log("Mined Address:", hookAddress);
        console.log("Use this Salt:", vm.toString(salt));
    }
}