// scripts/DeployMultisigEscrow.s.sol
// Foundry script to deploy MultisigRentEscrow.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {MultisigRentEscrow} from "../contracts/MultisigRentEscrow.sol";

contract DeployMultisigEscrow is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        MultisigRentEscrow escrow = new MultisigRentEscrow();
        console.log("MultisigRentEscrow deployed to:", address(escrow));
        vm.stopBroadcast();
    }
}
