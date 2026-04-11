// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../contracts/MultisigRentEscrow.sol";

contract MultisigRentEscrowTest is Test {
    MultisigRentEscrow escrow;
    address landlord = address(0xB);
    address renter = address(0xA);
    address[] renterSignatories;
    address[] landlordSignatories;
    string inventoryUri = "ipfs://property-inventory-123";

    function setUp() public {
        escrow = new MultisigRentEscrow();
        renterSignatories.push(address(0xC));
        renterSignatories.push(address(0xD));
        renterSignatories.push(address(0xE));
        landlordSignatories.push(address(0xF));
        landlordSignatories.push(address(0x10));
        landlordSignatories.push(address(0x11));
    }

    function testMultisigSetupAndNFTMint() public {
        vm.deal(renter, 2 ether);
        vm.prank(renter);
        uint256 escrowId = escrow.createEscrow{value: 1 ether}(
            landlord,
            renterSignatories,
            landlordSignatories,
            4,
            inventoryUri
        );
        (
            address escrowRenter,
            address escrowLandlord,
            address[] memory renterSigs,
            address[] memory landlordSigs,
            uint256 quorum,
            uint256 balance,
            bool released,
            uint256 signatures,
            uint256 inventoryNftId,
            bool multisigConfirmed
        ) = escrow.getEscrow(escrowId);
        assertEq(escrowRenter, renter);
        assertEq(escrowLandlord, landlord);
        assertEq(renterSigs.length, 3);
        assertEq(landlordSigs.length, 3);
        assertEq(quorum, 4);
        assertEq(balance, 1 ether);
        assertEq(released, false);
        assertEq(multisigConfirmed, false);
        assertEq(escrow.tokenURI(inventoryNftId), inventoryUri);
    }

    function testMultisigConfirmationAndRelease() public {
        vm.deal(renter, 2 ether);
        vm.prank(renter);
        uint256 escrowId = escrow.createEscrow{value: 1 ether}(
            landlord,
            renterSignatories,
            landlordSignatories,
            4,
            inventoryUri
        );
        // Confirm multisig
        vm.prank(renter);
        escrow.confirmMultisig(escrowId);
        (, , , , , , , , , bool multisigConfirmed) = escrow.getEscrow(escrowId);
        assertEq(multisigConfirmed, true);
        // Sign release by 4 signatories
        vm.prank(renterSignatories[0]);
        escrow.signRelease(escrowId);
        vm.prank(renterSignatories[1]);
        escrow.signRelease(escrowId);
        vm.prank(landlordSignatories[0]);
        escrow.signRelease(escrowId);
        vm.prank(landlordSignatories[1]);
        escrow.signRelease(escrowId);
        (, , , , , , bool released, , , ) = escrow.getEscrow(escrowId);
        assertEq(released, true);
    }
}
