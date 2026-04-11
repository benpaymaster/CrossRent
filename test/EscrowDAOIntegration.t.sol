// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
import "forge-std/Test.sol";
import "../contracts/RentEscrowStateMachine.sol";
import "../contracts/DisputeResolutionDAO.sol";

contract EscrowDAOIntegrationTest is Test {
    RentEscrowStateMachine escrow;
    DisputeResolutionDAO dao;
    address renter = address(0x1);
    address landlord = address(0x2);
    address voter1 = address(0x3);
    address voter2 = address(0x4);
    uint256 deposit = 1 ether;
    uint256 rent = 2 ether;

    function setUp() public {
    dao = new DisputeResolutionDAO();

    escrow = new RentEscrowStateMachine();

    address admin = address(this);

    escrow.initialize(
        renter,
        landlord,
        deposit,
        rent,
        address(dao),
        admin
    );
}

    function testDisputeReferralAndFullRefund() public {
        // Deposit and rent paid
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        // Raise dispute
        vm.prank(renter);
        escrow.raiseDispute();
        uint256 disputeId = escrow.disputeId();
        // Voters vote for full refund
        vm.prank(voter1);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.FullRefund);
        vm.prank(voter2);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.FullRefund);
        // Fast-forward 7 days
        vm.warp(block.timestamp + 7 days + 1);
        dao.resolveDispute(disputeId);
        // Apply outcome in escrow
        vm.prank(renter);
        escrow.applyDisputeOutcome();
        assertEq(uint8(escrow.state()), uint8(RentEscrowStateMachine.State.Refunded));    }

    function testDisputeReferralAndPartialRefund() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        vm.prank(renter);
        escrow.raiseDispute();
        uint256 disputeId = escrow.disputeId();
        vm.prank(voter1);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.PartialRefund);
        vm.prank(voter2);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.PartialRefund);
        vm.warp(block.timestamp + 7 days + 1);
        dao.resolveDispute(disputeId);
        vm.prank(renter);
        escrow.applyDisputeOutcome();
        assertEq(uint8(escrow.state()), uint8(RentEscrowStateMachine.State.Refunded));    }

    function testDisputeReferralAndNoRefund() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        vm.prank(renter);
        escrow.raiseDispute();
        uint256 disputeId = escrow.disputeId();
        vm.prank(voter1);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.NoRefund);
        vm.prank(voter2);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.NoRefund);
        vm.warp(block.timestamp + 7 days + 1);
        dao.resolveDispute(disputeId);
        vm.prank(renter);
        escrow.applyDisputeOutcome();
        assertEq(escrow.state(), RentEscrowStateMachine.State.Completed);
    }

    function testAppealFlow() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        vm.prank(renter);
        escrow.raiseDispute();
        uint256 disputeId = escrow.disputeId();
        vm.prank(voter1);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.NoRefund);
        vm.prank(voter2);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.NoRefund);
        vm.warp(block.timestamp + 7 days + 1);
        dao.resolveDispute(disputeId);
        // Appeal
        vm.prank(renter);
        dao.requestAppeal(disputeId);
        // Voters vote for full refund on appeal
        vm.prank(voter1);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.FullRefund);
        vm.prank(voter2);
        dao.vote(disputeId, DisputeResolutionDAO.Outcome.FullRefund);
        vm.warp(block.timestamp + 7 days + 1);
        dao.resolveDispute(disputeId);
        vm.prank(renter);
        escrow.applyDisputeOutcome();
        assertEq(uint8(escrow.state()), uint8(RentEscrowStateMachine.State.Refunded));    }
}
