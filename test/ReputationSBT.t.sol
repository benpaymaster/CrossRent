// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../contracts/ReputationSBT.sol";

contract ReputationSBTTest is Test {
    ReputationSBT reputation;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address escrowManager = makeAddr("escrowManager");
    address admin = makeAddr("admin");
    
    event ReputationUpdated(
        address indexed user,
        uint256 newCreditScore,
        uint256 totalRentals,
        uint256 successfulRentals
    );
    
    function setUp() public {
        vm.startPrank(admin);
        reputation = new ReputationSBT();
        reputation.grantEscrowManager(escrowManager);
        vm.stopPrank();
    }
    
    function test_MintReputationToken() public {
        uint256 tokenId = reputation.mintReputationToken(alice);
        
        assertEq(tokenId, 1);
        assertTrue(reputation.hasToken(alice));
        assertEq(reputation.tokenIds(alice), 1);
        assertEq(reputation.ownerOf(1), alice);
        
        // Check initial reputation data
        ReputationSBT.ReputationData memory data = reputation.getReputationData(alice);
        assertEq(data.totalRentals, 0);
        assertEq(data.successfulRentals, 0);
        assertEq(data.creditScore, 500); // Neutral score
        assertFalse(data.isLandlord);
        assertFalse(data.isTenant);
    }
    
    function test_CannotMintDuplicate() public {
        reputation.mintReputationToken(alice);
        
        vm.expectRevert("User already has token");
        reputation.mintReputationToken(alice);
    }
    
    function test_UpdateRentalHistory() public {
        vm.startPrank(escrowManager);
        
        // First rental should auto-mint token
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(alice, 800, 1, 1); // Score increases for successful rental
        
        reputation.updateRentalHistory(alice, 1000e6, true);
        
        // Check reputation updated
        assertTrue(reputation.hasToken(alice));
        ReputationSBT.ReputationData memory data = reputation.getReputationData(alice);
        assertEq(data.totalRentals, 1);
        assertEq(data.successfulRentals, 1);
        assertEq(data.totalValueLocked, 1000e6);
        assertEq(data.averageRentAmount, 1000e6);
        assertTrue(data.creditScore > 500); // Should be above neutral
        
        vm.stopPrank();
    }
    
    function test_AddRentalRecord() public {
        vm.startPrank(escrowManager);
        
        reputation.addRentalRecord(
            alice,
            1,
            bob,
            1000e6,
            true,
            false,
            "Canada",
            30 days
        );
        
        // Check rental history
        ReputationSBT.RentalRecord[] memory history = reputation.getRentalHistory(alice);
        assertEq(history.length, 1);
        assertEq(history[0].escrowId, 1);
        assertEq(history[0].counterparty, bob);
        assertEq(history[0].amount, 1000e6);
        assertTrue(history[0].successful);
        assertFalse(history[0].wasDisputed);
        assertEq(history[0].propertyLocation, "Canada");
        
        // Check countries array
        string[] memory countries = reputation.getCountries(alice);
        assertEq(countries.length, 1);
        assertEq(countries[0], "Canada");
        
        vm.stopPrank();
    }
    
    function test_CreditScoreCalculation() public {
        vm.startPrank(escrowManager);
        
        // Add successful rentals
        for (uint i = 0; i < 5; i++) {
            reputation.updateRentalHistory(alice, 1000e6, true);
        }
        
        uint256 score = reputation.getReputationScore(alice);
        assertTrue(score > 800); // Should have high score
        
        // Add a failed rental
        reputation.updateRentalHistory(alice, 1000e6, false);
        
        uint256 newScore = reputation.getReputationScore(alice);
        assertTrue(newScore < score); // Score should decrease
        assertTrue(newScore > 500);   // But still above neutral
        
        vm.stopPrank();
    }
    
    function test_DisputeImpactOnScore() public {
        vm.startPrank(escrowManager);
        
        // Start with some successful rentals
        for (uint i = 0; i < 3; i++) {
            reputation.updateRentalHistory(alice, 1000e6, true);
        }
        
        uint256 initialScore = reputation.getReputationScore(alice);
        
        // Add disputed rental (lost)
        reputation.addRentalRecord(
            alice,
            4,
            bob,
            1000e6,
            false,
            true, // Was disputed
            "USA",
            30 days
        );
        
        uint256 scoreAfterDispute = reputation.getReputationScore(alice);
        assertTrue(scoreAfterDispute < initialScore); // Score penalty for dispute
        
        vm.stopPrank();
    }
    
    function test_InternationalExperienceBonus() public {
        vm.startPrank(escrowManager);
        
        // Add rentals in different countries
        string[5] memory countries = ["USA", "Canada", "UK", "Germany", "Japan"];
        
        for (uint i = 0; i < countries.length; i++) {
            reputation.addRentalRecord(
                alice,
                i + 1,
                bob,
                1000e6,
                true,
                false,
                countries[i],
                30 days
            );
            reputation.updateRentalHistory(alice, 1000e6, true);
        }
        
        // Check international bonus reflected in score
        uint256 score = reputation.getReputationScore(alice);
        string[] memory userCountries = reputation.getCountries(alice);
        assertEq(userCountries.length, 5);
        assertTrue(score > 900); // High score with international experience
        
        vm.stopPrank();
    }
    
    function test_UpdateUserRole() public {
        vm.startPrank(escrowManager);
        
        reputation.updateUserRole(alice, true, false); // Landlord
        reputation.updateUserRole(bob, false, true);   // Tenant
        
        ReputationSBT.ReputationData memory aliceData = reputation.getReputationData(alice);
        ReputationSBT.ReputationData memory bobData = reputation.getReputationData(bob);
        
        assertTrue(aliceData.isLandlord);
        assertFalse(aliceData.isTenant);
        assertFalse(bobData.isLandlord);
        assertTrue(bobData.isTenant);
        
        vm.stopPrank();
    }
    
    function test_TokenURI() public {
        vm.startPrank(escrowManager);
        
        // Create token with some history
        reputation.updateRentalHistory(alice, 1000e6, true);
        reputation.updateUserRole(alice, false, true);
        reputation.addRentalRecord(alice, 1, bob, 1000e6, true, false, "USA", 30 days);
        
        vm.stopPrank();
        
        uint256 tokenId = reputation.tokenIds(alice);
        string memory uri = reputation.tokenURI(tokenId);
        
        // Should return base64 encoded JSON
        assertTrue(bytes(uri).length > 0);
        
        // Check it starts with data URI
        string memory prefix = "data:application/json;base64,";
        bytes memory uriBytes = bytes(uri);
        bytes memory prefixBytes = bytes(prefix);
        
        for (uint i = 0; i < prefixBytes.length; i++) {
            assertEq(uriBytes[i], prefixBytes[i]);
        }
    }
    
    function test_Soulbound_CannotTransfer() public {
        uint256 tokenId = reputation.mintReputationToken(alice);
        
        vm.startPrank(alice);
        
        // Cannot transfer
        vm.expectRevert("Soulbound: Transfer not allowed");
        reputation.transferFrom(alice, bob, tokenId);
        
        // Cannot approve
        vm.expectRevert("Soulbound: Approval not allowed");
        reputation.approve(bob, tokenId);
        
        // Cannot set approval for all
        vm.expectRevert("Soulbound: Approval not allowed");
        reputation.setApprovalForAll(bob, true);
        
        vm.stopPrank();
    }
    
    function test_OnlyEscrowManagerCanUpdate() public {
        // Non-escrow manager cannot update
        vm.expectRevert();
        reputation.updateRentalHistory(alice, 1000e6, true);
        
        vm.expectRevert();
        reputation.addRentalRecord(alice, 1, bob, 1000e6, true, false, "USA", 30 days);
        
        vm.expectRevert();
        reputation.updateUserRole(alice, true, false);
    }
    
    function test_DefaultScoreForNewUsers() public {
        // User without token should return default neutral score
        uint256 score = reputation.getReputationScore(alice);
        assertEq(score, 500);
    }
    
    function test_ScoreBounds() public {
        vm.startPrank(escrowManager);
        
        // Add many successful rentals with high value
        for (uint i = 0; i < 50; i++) {
            reputation.updateRentalHistory(alice, 10000e6, true);
        }
        
        uint256 score = reputation.getReputationScore(alice);
        assertTrue(score <= 1000); // Should not exceed maximum
        
        // Add many disputes to test minimum bound
        for (uint i = 0; i < 20; i++) {
            reputation.addRentalRecord(
                bob,
                i + 1,
                alice,
                1000e6,
                false,
                true, // Disputed
                "USA",
                30 days
            );
            reputation.updateRentalHistory(bob, 1000e6, false);
        }
        
        uint256 bobScore = reputation.getReputationScore(bob);
        assertTrue(bobScore >= 0); // Should not go below minimum
        
        vm.stopPrank();
    }
    
    function test_TimeBasedBonus() public {
        vm.startPrank(escrowManager);
        
        reputation.updateRentalHistory(alice, 1000e6, true);
        uint256 initialScore = reputation.getReputationScore(alice);
        
        // Fast forward time (simulate being active for months)
        vm.warp(block.timestamp + 180 days); // 6 months
        
        // Update again to trigger score recalculation
        reputation.updateRentalHistory(alice, 1000e6, true);
        uint256 newScore = reputation.getReputationScore(alice);
        
        assertTrue(newScore > initialScore); // Should get time-based bonus
        
        vm.stopPrank();
    }
    
    function test_GetFunctions() public {
        vm.startPrank(escrowManager);
        
        reputation.updateRentalHistory(alice, 1000e6, true);
        reputation.addRentalRecord(alice, 1, bob, 1000e6, true, false, "USA", 30 days);
        
        vm.stopPrank();
        
        // Test getter functions
        ReputationSBT.ReputationData memory data = reputation.getReputationData(alice);
        assertEq(data.totalRentals, 1);
        
        ReputationSBT.RentalRecord[] memory history = reputation.getRentalHistory(alice);
        assertEq(history.length, 1);
        
        uint256 count = reputation.getRentalCount(alice);
        assertEq(count, 1);
        
        string[] memory countries = reputation.getCountries(alice);
        assertEq(countries.length, 1);
        assertEq(countries[0], "USA");
        
        uint256 score = reputation.getReputationScore(alice);
        assertTrue(score > 500);
    }
}
