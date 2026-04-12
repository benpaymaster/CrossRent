// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

/// @title Deploy
/// @dev Complete deployment script for the CrossRent / RentCredit system on Arc
contract Deploy is Script {
    // TODO: Replace with the official Arc USDC address for the hackathon network
    address constant USDC_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant EURC_ADDRESS = 0x2E8D98fd126a32362F2Bd8aA427E59a1ec63F780;

    address public reputation;
    address public riskBufferVault;
    address public rentCreditEscrow;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== CrossRent / RentCredit Deployment ===");
        console.log("Deployer:", deployer);
        console.log("USDC:", USDC_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Reputation SBT
        ReputationSBT sbt = new ReputationSBT();
        reputation = address(sbt);
        console.log("ReputationSBT deployed at:", reputation);

        // 2. Deploy Risk Buffer Vault (ERC4626)
        RiskBufferVault vault = new RiskBufferVault(
            IERC20(USDC_ADDRESS),
            "CrossRent Risk Buffer",
            "CRB"
        );
        riskBufferVault = address(vault);
        console.log("RiskBufferVault deployed at:", riskBufferVault);

        // 3. Deploy RentCreditEscrow
        RentCreditEscrow escrow = new RentCreditEscrow(
            USDC_ADDRESS,
            EURC_ADDRESS,
            reputation,
            riskBufferVault
        );
        rentCreditEscrow = address(escrow);
        console.log("RentCreditEscrow deployed at:", rentCreditEscrow);

        // 4. Wire permissions / roles
        console.log("Configuring roles...");

        // Allow escrow to manage SBT reputation
        sbt.grantEscrowManager(rentCreditEscrow);

        // Allow escrow to lock / release buffers in vault
        vault.grantEscrowManager(rentCreditEscrow);

        // Escrow roles
        escrow.grantRole(escrow.DISPUTE_RESOLVER_ROLE(), deployer);
        escrow.grantRole(escrow.CROSS_CHAIN_RELAYER_ROLE(), deployer);

        // Vault risk manager (so deployer can tweak parameters)
        vault.grantRole(vault.RISK_MANAGER_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("ReputationSBT:", reputation);
        console.log("RiskBufferVault:", riskBufferVault);
        console.log("RentCreditEscrow:", rentCreditEscrow);
        console.log("===========================");
    }
}
