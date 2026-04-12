// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

/**
 * @title DemoSetup
 * @dev Sets up demo scenarios for the RentCredit system
 */
contract DemoSetup is Script {
    RentCreditEscrow escrow;
    ReputationSBT reputation;
    RiskBufferVault vault;
    
    // Demo addresses
    address alice = 0x1234567890123456789012345678901234567890;
    address bob = 0x2345678901234567890123456789012345678901;
    address charlie = 0x3456789012345678901234567890123456789012;
    
    function run() external {
        // Load deployed contract addresses from environment
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        address reputationAddress = vm.envAddress("REPUTATION_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        
        escrow = RentCreditEscrow(escrowAddress);
        reputation = ReputationSBT(reputationAddress);
        vault = RiskBufferVault(vaultAddress);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Setting up demo scenarios...");
        
        // Demo 1: Create sample reputation tokens
        _setupReputationTokens();
        
        // Demo 2: Setup yield strategy for vault
        _setupYieldStrategy();
        
        // Demo 3: Grant demo roles
        _setupDemoRoles();
        
        vm.stopBroadcast();
        
        console.log("Demo setup complete!");
    }
    
    function _setupReputationTokens() internal {
        console.log("Creating demo reputation tokens...");
        
        // Alice - Experienced tenant
        reputation.mintReputationToken(alice);
        reputation.updateUserRole(alice, false, true);
        
        // Simulate rental history for Alice
        for (uint i = 0; i < 5; i++) {
            reputation.updateRentalHistory(alice, 1000e6, true); // $1000 successful rentals
            reputation.addRentalRecord(
                alice,
                i + 1,
                bob,
                1000e6,
                true,
                false,
                "USA",
                30 days
            );
        }
        
        // Bob - Landlord with mixed history
        reputation.mintReputationToken(bob);
        reputation.updateUserRole(bob, true, false);
        
        // Simulate mixed history for Bob
        for (uint i = 0; i < 3; i++) {
            reputation.updateRentalHistory(bob, 2000e6, true); // $2000 successful
        }
        reputation.updateRentalHistory(bob, 1500e6, false); // One failed rental
        reputation.addRentalRecord(
            bob,
            6,
            charlie,
            1500e6,
            false,
            true,
            "Canada",
            45 days
        );
        
        // Charlie - New user
        reputation.mintReputationToken(charlie);
        reputation.updateUserRole(charlie, false, true);
        
        console.log("Demo reputation tokens created");
    }
    
    function _setupYieldStrategy() internal {
        console.log("Setting up yield strategy...");
        
        // Configure vault yield strategy
        vault.setYieldStrategy(
            true,           // enabled
            400,           // 4% target APY
            7500,          // 75% max utilization
            1000,          // 10% rebalance threshold
            address(0)     // no external strategy for demo
        );
        
        // Set risk parameters
        vault.setRiskParameters(
            50000e6,       // $50k max individual lock
            5000000e6,     // $5M total risk limit
            1500           // 15% liquidity reserve
        );
        
        console.log("Yield strategy configured");
    }
    
    function _setupDemoRoles() internal {
        console.log("Setting up demo roles...");
        
        // Grant dispute resolver role to deployer for demo
        escrow.grantRole(escrow.DISPUTE_RESOLVER_ROLE(), msg.sender);
        
        // Grant cross-chain relayer role for demo
        escrow.grantRole(escrow.CROSS_CHAIN_RELAYER_ROLE(), msg.sender);
        
        // Grant risk manager role
        vault.grantRole(vault.RISK_MANAGER_ROLE(), msg.sender);
        
        console.log("Demo roles granted");
    }
    
    // Helper function to create a demo escrow
    function createDemoEscrow() external view {
        require(msg.sender != address(0), "Invalid sender");
        
        // Create automation conditions
        // RentCreditEscrow.AutomationConditions memory conditions = RentCreditEscrow.AutomationConditions({
        //     requiresPhysicalInspection: true,
        //     requiresTenantConfirmation: false,
        //     requiresPropertyDamageCheck: true,
        //     maxDamageThreshold: 500e6, // $500 max damage
        //     gracePeriodDays: 7
        // });
        
        // Create demo property hash
        // bytes32 propertyHash = keccak256(abi.encodePacked("123 Main St, Toronto, ON"));
        
        console.log("Use this function to create demo escrows after deployment");
        console.log("Deposit: 2000 USDC, Rent: 1000 USDC, Duration: 30 days");
    }
}
