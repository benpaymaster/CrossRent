// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

// Mock USDC for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract SimpleMultiTokenTest is Test {
    RentCreditEscrow escrow;
    ReputationSBT reputation;
    RiskBufferVault vault;
    MockToken usdc;
    MockToken eurc;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockToken("Mock USDC", "USDC");
        eurc = new MockToken("Mock EURC", "EURC");
        
        // Deploy contracts
        reputation = new ReputationSBT();
        vault = new RiskBufferVault(usdc, "Risk Buffer", "RB");
        escrow = new RentCreditEscrow(address(usdc), address(eurc), address(reputation), address(vault));
        
        // Setup permissions
        reputation.grantEscrowManager(address(escrow));
        vault.grantEscrowManager(address(escrow));
    }

    function test_MultiTokenSupport() public {
        // Test that both USDC and EURC are supported
        assertTrue(escrow.isTokenSupported(address(usdc)));
        assertTrue(escrow.isTokenSupported(address(eurc)));
    }

    function test_CreateEscrowWithUSDC() public {
        // Setup - mint tokens to alice and approve both escrow and vault
        usdc.mint(alice, 3000e6);
        vm.startPrank(alice);
        usdc.approve(address(escrow), 3000e6);
        usdc.approve(address(vault), 1000e6); // Vault needs approval for buffer
        vm.stopPrank();

        // Create escrow with USDC
        vm.prank(alice);
        uint256 escrowId = escrow.createEscrow(
            bob,
            2000e6, // deposit
            1000e6, // rent
            30 days, // duration
            keccak256("property123"),
            RentCreditEscrow.AutomationConditions({
                requiresPhysicalInspection: false,
                requiresTenantConfirmation: false,
                requiresPropertyDamageCheck: false,
                maxDamageThreshold: 100e6,
                gracePeriodDays: 3
            }),
            0, // crossChainOriginId
            address(usdc) // token
        );

        // Verify escrow was created with correct token
        assertEq(escrow.getEscrowToken(escrowId), address(usdc));
    }

    function test_CreateEscrowWithEURC() public {
        // Setup - mint tokens to alice and approve the escrow contract
        eurc.mint(alice, 3000e6);
        vm.startPrank(alice);
        eurc.approve(address(escrow), 3000e6);
        
        // Also approve vault for buffer if needed
        eurc.approve(address(vault), 1000e6);
        vm.stopPrank();

        // Create escrow with EURC
        vm.prank(alice);
        uint256 escrowId = escrow.createEscrow(
            bob,
            2000e6, // deposit
            1000e6, // rent
            30 days, // duration
            keccak256("property123"),
            RentCreditEscrow.AutomationConditions({
                requiresPhysicalInspection: false,
                requiresTenantConfirmation: false,
                requiresPropertyDamageCheck: false,
                maxDamageThreshold: 100e6,
                gracePeriodDays: 3
            }),
            0, // crossChainOriginId
            address(eurc) // token
        );

        // Verify escrow was created with correct token
        assertEq(escrow.getEscrowToken(escrowId), address(eurc));
    }

    function test_ReputationMultiTokenTracking() public {
        // Test that reputation system tracks both tokens
        (,,,, uint256 usdcVolume, uint256 eurcVolume, bool isMultiToken) = reputation.getUserSummary(alice);
        
        assertEq(usdcVolume, 0);
        assertEq(eurcVolume, 0);
        assertFalse(isMultiToken);
    }
}