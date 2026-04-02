// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DisputeResolutionDAO {
    enum Outcome { None, FullRefund, PartialRefund, NoRefund }
    struct Dispute {
        address escrow;
        address renter;
        address landlord;
        uint256 depositAmount;
        uint256 createdAt;
        Outcome outcome;
        uint256 votesFull;
        uint256 votesPartial;
        uint256 votesNone;
        bool resolved;
        bool appealed;
    }

    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public disputeCount;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event DisputeCreated(uint256 indexed disputeId, address escrow);
    event Voted(uint256 indexed disputeId, address voter, Outcome outcome);
    event DisputeResolved(uint256 indexed disputeId, Outcome outcome);
    event AppealRequested(uint256 indexed disputeId);

    function createDispute(address escrow, address renter, address landlord, uint256 depositAmount) external returns (uint256) {
        disputeCount++;
        disputes[disputeCount] = Dispute({
            escrow: escrow,
            renter: renter,
            landlord: landlord,
            depositAmount: depositAmount,
            createdAt: block.timestamp,
            outcome: Outcome.None,
            votesFull: 0,
            votesPartial: 0,
            votesNone: 0,
            resolved: false,
            appealed: false
        });
        emit DisputeCreated(disputeCount, escrow);
        return disputeCount;
    }

    function vote(uint256 disputeId, Outcome outcome) external {
        Dispute storage d = disputes[disputeId];
        require(block.timestamp <= d.createdAt + VOTING_PERIOD, "Voting ended");
        require(!d.resolved, "Already resolved");
        require(!hasVoted[disputeId][msg.sender], "Already voted");
        hasVoted[disputeId][msg.sender] = true;
        if (outcome == Outcome.FullRefund) d.votesFull++;
        else if (outcome == Outcome.PartialRefund) d.votesPartial++;
        else if (outcome == Outcome.NoRefund) d.votesNone++;
        emit Voted(disputeId, msg.sender, outcome);
    }

    function resolveDispute(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        require(block.timestamp > d.createdAt + VOTING_PERIOD, "Voting not ended");
        require(!d.resolved, "Already resolved");
        d.resolved = true;
        if (d.votesFull >= d.votesPartial && d.votesFull >= d.votesNone) {
            d.outcome = Outcome.FullRefund;
        } else if (d.votesPartial >= d.votesFull && d.votesPartial >= d.votesNone) {
            d.outcome = Outcome.PartialRefund;
        } else {
            d.outcome = Outcome.NoRefund;
        }
        emit DisputeResolved(disputeId, d.outcome);
    }

    function requestAppeal(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        require(d.resolved, "Not resolved yet");
        require(!d.appealed, "Already appealed");
        require(msg.sender == d.renter || msg.sender == d.landlord, "Unauthorized");
        d.appealed = true;
        d.resolved = false;
        d.createdAt = block.timestamp;
        d.votesFull = 0;
        d.votesPartial = 0;
        d.votesNone = 0;
        d.outcome = Outcome.None;
        emit AppealRequested(disputeId);
    }
}
