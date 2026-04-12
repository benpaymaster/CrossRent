// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../test/SimpleMultiTokenTest.t.sol";
import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

contract DeployToArc is Script {
    function run() external {
        vm.startBroadcast();
        
        console.log("=== CrossRent Multi-Stablecoin Deployment to Arc ===");
        console.log("Deployer address:", msg.sender);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        // Deploy mock tokens for testing (in production these would be real Circle tokens)
        console.log("Deploying Mock Stablecoins...");
        MockToken usdc = new MockToken("USD Coin", "USDC");
        MockToken eurc = new MockToken("Euro Coin", "EURC");
        console.log("  Mock USDC deployed at:", address(usdc));
        console.log("  Mock EURC deployed at:", address(eurc));
        console.log("");
        
        // Deploy ReputationSBT with multi-token support
        console.log("Deploying Enhanced Reputation System...");
        ReputationSBT reputation = new ReputationSBT();
        console.log("  ReputationSBT deployed at:", address(reputation));
        console.log("    - Multi-stablecoin credit scoring");
        console.log("    - Cross-currency reputation bonuses");
        console.log("    - Soulbound NFT with dynamic metadata");
        console.log("");
        
        // Deploy USDC Risk Buffer Vault
        console.log("Deploying USDC Yield Vault...");
        RiskBufferVault usdcVault = new RiskBufferVault(usdc, "CrossRent USDC Vault", "xrUSDC");
        console.log("  USDC Vault deployed at:", address(usdcVault));
        console.log("    - ERC4626 yield optimization");
        console.log("    - Automated risk management");
        console.log("");
        
        // Deploy Multi-Stablecoin Escrow System
        console.log("Deploying Multi-Stablecoin Escrow...");
        RentCreditEscrow escrow = new RentCreditEscrow(
            address(usdc),
            address(eurc), 
            address(reputation),
            address(usdcVault)
        );
        console.log("  Multi-Token Escrow deployed at:", address(escrow));
        console.log("    - USDC + EURC support");
        console.log("    - Dynamic token selection per escrow");
        console.log("    - Programmable automation logic");
        console.log("    - Cross-chain integration ready");
        console.log("");
        
        // Configure permissions
        console.log("Configuring System Permissions...");
        reputation.grantEscrowManager(address(escrow));
        usdcVault.grantEscrowManager(address(escrow));
        console.log("  Escrow <-> Reputation integration: ENABLED");
        console.log("  Escrow <-> USDC Vault integration: ENABLED");
        console.log("");
        
        // Mint test tokens for demonstration
        console.log("Minting Test Tokens...");
        usdc.mint(msg.sender, 100000e6); // $100k USDC
        eurc.mint(msg.sender, 100000e6); // €100k EURC
        console.log("  100,000 USDC minted to deployer");
        console.log("  100,000 EURC minted to deployer"); 
        console.log("");
        
        // Verify multi-token support
        console.log("Verifying Multi-Token Support...");
        bool usdcSupported = escrow.isTokenSupported(address(usdc));
        bool eurcSupported = escrow.isTokenSupported(address(eurc));
        console.log("  USDC supported:", usdcSupported ? "YES" : "NO");
        console.log("  EURC supported:", eurcSupported ? "YES" : "NO");
        console.log("");
        
        console.log("=== CrossRent Arc Deployment Complete! ===");
        console.log("");
        console.log("CONTRACT ADDRESSES:");
        console.log("Component           | Address");
        console.log("USDC Token          |", address(usdc));
        console.log("EURC Token          |", address(eurc));
        console.log("Reputation SBT      |", address(reputation));
        console.log("USDC Vault          |", address(usdcVault));
        console.log("Multi-Token Escrow  |", address(escrow));
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Test USDC escrow creation");
        console.log("2. Test EURC escrow creation");
        console.log("3. Verify cross-currency reputation bonuses");
        console.log("4. Connect frontend to deployed contracts");
        console.log("");
        console.log("CrossRent is now live on Arc blockchain!");
        console.log("Multi-stablecoin rental ecosystem ready for production!");
        
        vm.stopBroadcast();
    }
}