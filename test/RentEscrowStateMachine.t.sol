// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
import "forge-std/Test.sol";
import "../contracts/RentEscrowStateMachine.sol";

contract RentEscrowStateMachineTest is Test {
    RentEscrowStateMachine escrow;
    address renter = address(0x1);
    address landlord = address(0x2);
    uint256 deposit = 1 ether;
    uint256 rent = 2 ether;

    function setUp() public {
    escrow = new RentEscrowStateMachine(renter, landlord, deposit, rent);

    vm.deal(renter, 10 ether);
    vm.deal(landlord, 10 ether);
    }

    function testCannotPayRentTwice() public {
    vm.deal(renter, 10 ether);

    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(renter);
    escrow.payRent{value: rent};

    vm.prank(renter);
    vm.expectRevert();
    escrow.payRent{value: rent};
    }

    function testOnlyRenterCanRaiseDispute() public {
    vm.deal(renter, 10 ether);

    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(address(0x999));
    vm.expectRevert();
    escrow.raiseDispute();
    }

    function testCannotRefundBeforeDeposit() public {
    vm.prank(landlord);
    vm.expectRevert();
    escrow.refundDeposit();
    }

    function testCannotPayDepositTwice() public {
    vm.deal(renter, 10 ether);

    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(renter);
    vm.expectRevert();
    escrow.payDeposit{value: deposit};
    }

    function testRentFailsWithoutDeposit() public {
    vm.prank(renter);
    vm.expectRevert();
    escrow.payRent{value: rent}();
    }

    function testDepositWrongAmountReverts() public {
    vm.prank(renter);
    vm.expectRevert();
    escrow.payDeposit{value: 0.5 ether}();
    }

    function testOnlyLandlordCanCompleteLease() public {
    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(renter);
    escrow.payRent{value: rent};

    vm.prank(address(0x999));
    vm.expectRevert();
    escrow.completeLease();
    }

    function testCannotSkipToCompleted() public {
    vm.prank(landlord);
    vm.expectRevert();
    escrow.completeLease();
    }

    function testCannotRaiseDisputeTwice() public {
    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(renter);
    escrow.raiseDispute();

    vm.prank(renter);
    vm.expectRevert();
    escrow.raiseDispute();
    }

    function testDepositTransfersFunds() public {
    vm.deal(renter, 10 ether);

    vm.prank(renter);
    escrow.payDeposit{value: deposit}();

    assertEq(address(escrow).balance, deposit);
    }

    function testRefundReturnsFunds() public {
    vm.deal(renter, 10 ether);

    vm.prank(renter);
    escrow.payDeposit{value: deposit}();

    uint256 balanceBefore = renter.balance;

    vm.prank(landlord);
    escrow.refundDeposit();

    assertEq(renter.balance, balanceBefore + deposit);
    }

    function testDepositPayment() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        assertEq(escrow.state(), RentEscrowStateMachine.State.DepositPaid);
        assertEq(escrow.depositPaid(), deposit);
    }

    function testNoActionsAfterCompletion() public {
    vm.prank(renter);
    escrow.payDeposit{value: deposit};

    vm.prank(renter);
    escrow.payRent{value: rent};

    vm.prank(landlord);
    escrow.completeLease();

    vm.prank(renter);
    vm.expectRevert();
    escrow.raiseDispute();
    }

    function testRentPayment() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        assertEq(escrow.state(), RentEscrowStateMachine.State.RentPaid);
        assertEq(escrow.rentPaid(), rent);
    }

    function testCompleteLease() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.payRent{value: rent}();
        vm.prank(landlord);
        escrow.completeLease();
        assertEq(escrow.state(), RentEscrowStateMachine.State.Completed);
    }

    function testRefundDeposit() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(landlord);
        escrow.refundDeposit();
        assertEq(escrow.state(), RentEscrowStateMachine.State.Refunded);
    }

    function testRaiseDispute() public {
        vm.prank(renter);
        escrow.payDeposit{value: deposit}();
        vm.prank(renter);
        escrow.raiseDispute();
        assertEq(escrow.state(), RentEscrowStateMachine.State.Disputed);
    }
}
