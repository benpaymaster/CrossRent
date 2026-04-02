// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "../contracts/RentEscrowStateMachine.sol";

contract RentEscrowStateMachineTest is Test {
    RentEscrow escrow;
    address renter = address(0x1);
    address landlord = address(0x2);
    uint256 deposit = 1 ether;
    uint256 rent = 2 ether;

    function setUp() public {
        escrow = new RentEscrow(renter, landlord, deposit, rent);
    }

    function testDepositPayment() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        assertEq(escrow.state(), RentEscrow.State.DepositPaid);
        assertEq(escrow.depositPaid(), deposit);
    }

    function testRentPayment() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        assertEq(escrow.state(), RentEscrow.State.RentPaid);
        assertEq(escrow.rentPaid(), rent);
    }

    function testCompleteLease() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        vm.prank(landlord);
        escrow.completeLease();
        assertEq(escrow.state(), RentEscrow.State.Completed);
    }

    function testRefundDeposit() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(landlord);
        escrow.refundDeposit();
        assertEq(escrow.state(), RentEscrow.State.Refunded);
    }

    function testRaiseDispute() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.raiseDispute();
        assertEq(escrow.state(), RentEscrow.State.Disputed);
    }
}
