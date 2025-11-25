// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/OptimisticDemocracy.sol";

contract OptimisticDemocracyTest is Test {
    OptimisticDemocracy democracy;
    address[] voters;
    address proposer = address(0xA);
    address voter1 = address(0xB);
    address voter2 = address(0xC);
    address voter3 = address(0xD);
    uint256 challengePeriod = 1 days;

    function setUp() public {
        voters.push(voter1);
        voters.push(voter2);
        voters.push(voter3);
        democracy = new OptimisticDemocracy(voters, challengePeriod);
    }

    function testRaiseDispute() public {
        vm.prank(proposer);
        uint256 id = democracy.raiseDispute("Deposit not returned");
        (address p, , uint256 deadline, , , , , , , , , ) = democracy
            .getDispute(id);
        assertEq(p, proposer);
        assertGt(deadline, block.timestamp);
    }

    function testAppealAndDAOVote() public {
        vm.prank(proposer);
        uint256 id = democracy.raiseDispute("Deposit not returned");
        vm.prank(voter1);
        democracy.vote(id, false);
        vm.prank(voter2);
        democracy.vote(id, false);
        vm.prank(voter3);
        democracy.vote(id, true);
        vm.warp(block.timestamp + challengePeriod + 1);
        democracy.finalize(id);
        // Fund voter1 for appeal fee
        vm.deal(voter1, 0.02 ether);
        // Appeal
        vm.prank(voter1);
        democracy.appeal{value: 0.01 ether}(id);
        // DAO voting
        vm.prank(voter2);
        democracy.daoVote(id, true);
        vm.prank(voter3);
        democracy.daoVote(id, true);
        vm.prank(voter1);
        democracy.daoVote(id, false);
        // Fast forward DAO vote period
        vm.warp(block.timestamp + 7 days + 1);
        democracy.finalizeDAO(id);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            // proposer
            // description
            // challengeDeadline
            // votesFor
            // votesAgainst
            // status
            // appealed
            // appealFee
            // daoVoteDeadline
            // daoVotesFor
            // daoVotesAgainst
            bool finalOutcome
        ) = democracy.getDispute(id);
        assertEq(finalOutcome, true); // DAO votes 2 for, 1 against
    }
}
