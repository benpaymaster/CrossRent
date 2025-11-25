// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/MultisigRentEscrow.sol";

contract MultisigRentEscrowTest is Test {
    MultisigRentEscrow escrow;
    address[] signers;
    uint256 escrowId;

    function setUp() public {
        escrow = new MultisigRentEscrow();
        // 3 renter signatories, 3 landlord signatories
        for (uint256 i = 0; i < 6; i++) {
            signers.push(address(uint160(i + 1)));
        }
    }

    function testCreateEscrow() public {
        // Renter pays deposit
        vm.deal(address(this), 10 ether);
        escrowId = escrow.createEscrow{value: 1 ether}(signers, 4);
        (address[] memory s, uint256 q, uint256 bal, bool released, uint256 sigs) = escrow.getEscrow(escrowId);
        assertEq(s.length, 6);
        assertEq(q, 4);
        assertEq(bal, 1 ether);
        assertEq(released, false);
        assertEq(sigs, 0);
    }

    function testSignAndRelease() public {
        vm.deal(address(this), 10 ether);
        escrowId = escrow.createEscrow{value: 1 ether}(signers, 4);
        // 3 signers sign, deposit not released
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(signers[i]);
            escrow.signRelease(escrowId);
        }
        (, , , bool released, uint256 sigs) = escrow.getEscrow(escrowId);
        assertEq(released, false);
        assertEq(sigs, 3);
        // 4th signer signs, deposit released
        vm.prank(signers[3]);
        escrow.signRelease(escrowId);
        (, , , released, sigs) = escrow.getEscrow(escrowId);
        assertEq(released, true);
        assertEq(sigs, 4);
    }

    function testOnlySignatoryCanSign() public {
        vm.deal(address(this), 10 ether);
        escrowId = escrow.createEscrow{value: 1 ether}(signers, 4);
        address notSigner = address(100);
        vm.prank(notSigner);
        vm.expectRevert("Not a signatory");
        escrow.signRelease(escrowId);
    }

    function testNoDoubleSign() public {
        vm.deal(address(this), 10 ether);
        escrowId = escrow.createEscrow{value: 1 ether}(signers, 4);
        vm.prank(signers[0]);
        escrow.signRelease(escrowId);
        vm.prank(signers[0]);
        vm.expectRevert("Already signed");
        escrow.signRelease(escrowId);
    }
}
