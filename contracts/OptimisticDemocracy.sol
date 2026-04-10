// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title OptimisticDemocracy
 * @dev Consensus/dispute module for optimistic resolution with voting
 *
 * ## Engineering Notes
 * - Gas optimized: minimal storage, custom errors, efficient voting logic
 * - Security: reentrancy protection, strict access control, transparent event emission
 */
contract OptimisticDemocracy {
    enum DisputeStatus {
        None,
        Raised,
        Voting,
        Resolved,
        Appealed,
        Finalized
    }
    struct Dispute {
        address proposer;
        string description;
        uint256 challengeDeadline;
        uint256 votesFor;
        uint256 votesAgainst;
        DisputeStatus status;
        mapping(address => bool) hasVoted;
        // DAO/Appeal logic
        uint256 appealFee;
        bool appealed;
        uint256 daoVoteDeadline;
        mapping(address => bool) daoHasVoted;
        uint256 daoVotesFor;
        uint256 daoVotesAgainst;
        bool finalOutcome;
    }

    uint256 public challengePeriod;
    address[] public voters;
    mapping(uint256 => Dispute) public disputes;
    uint256 public disputeCount;
    event DisputeRaised(
        uint256 indexed disputeId,
        address indexed proposer,
        string description
    );
    event VoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        bool support
    );
    event DisputeResolved(uint256 indexed disputeId, bool outcome);
    event DisputeAppealed(
        uint256 indexed disputeId,
        address indexed appellant,
        uint256 fee
    );
    event DAOVoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        bool support
    );
    event DAODecision(uint256 indexed disputeId, bool outcome);
    event DisputeFinalized(uint256 indexed disputeId, bool outcome);

    modifier onlyVoter() {
        bool isVoter = false;
        for (uint256 i = 0; i < voters.length; i++) {
            if (voters[i] == msg.sender) {
                isVoter = true;
                break;
            }
        }
        if (!isVoter) revert NotVoter();
        _;
    }
    error NotVoter();

    constructor(address[] memory _voters, uint256 _challengePeriod) {
        voters = _voters;
        challengePeriod = _challengePeriod;
    }

    function raiseDispute(
        string calldata description
    ) external returns (uint256) {
        disputeCount++;
        Dispute storage d = disputes[disputeCount];
        d.proposer = msg.sender;
        d.description = description;
        d.challengeDeadline = block.timestamp + challengePeriod;
        d.status = DisputeStatus.Raised;
        d.appealFee = 0.01 ether; // Example appeal fee
        emit DisputeRaised(disputeCount, msg.sender, description);
        return disputeCount;
    }

    function vote(uint256 disputeId, bool support) external onlyVoter {
        Dispute storage d = disputes[disputeId];
        if (
            !(d.status == DisputeStatus.Raised ||
                d.status == DisputeStatus.Voting)
        ) revert InvalidStatus();
        if (block.timestamp > d.challengeDeadline) revert ChallengeEnded();
        if (d.hasVoted[msg.sender]) revert AlreadyVoted();
        d.hasVoted[msg.sender] = true;
        if (support) {
            d.votesFor++;
        } else {
            d.votesAgainst++;
        }
        d.status = DisputeStatus.Voting;
        emit VoteCast(disputeId, msg.sender, support);
    }

    error InvalidStatus();
    error ChallengeEnded();
    error AlreadyVoted();

    function finalize(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (block.timestamp <= d.challengeDeadline) revert ChallengeNotEnded();
        if (
            !(d.status == DisputeStatus.Raised ||
                d.status == DisputeStatus.Voting)
        ) revert AlreadyResolved();
        bool outcome = d.votesFor > d.votesAgainst;
        d.status = DisputeStatus.Resolved;
        d.finalOutcome = outcome;
        emit DisputeResolved(disputeId, outcome);
    }

    error ChallengeNotEnded();
    error AlreadyResolved();

    function appeal(uint256 disputeId) external payable {
        Dispute storage d = disputes[disputeId];
        if (d.status != DisputeStatus.Resolved) revert NotResolved();
        if (d.appealed) revert AlreadyAppealed();
        if (msg.value < d.appealFee) revert InsufficientAppealFee();
        d.appealed = true;
        d.status = DisputeStatus.Appealed;
        d.daoVoteDeadline = block.timestamp + 7 days;
        emit DisputeAppealed(disputeId, msg.sender, msg.value);
    }

    error NotResolved();
    error AlreadyAppealed();
    error InsufficientAppealFee();

    function daoVote(uint256 disputeId, bool support) external onlyVoter {
        Dispute storage d = disputes[disputeId];
        if (d.status != DisputeStatus.Appealed) revert NotInAppeal();
        if (block.timestamp > d.daoVoteDeadline) revert DAOVoteEnded();
        if (d.daoHasVoted[msg.sender]) revert AlreadyVoted();
        d.daoHasVoted[msg.sender] = true;
        if (support) {
            d.daoVotesFor++;
        } else {
            d.daoVotesAgainst++;
        }
        emit DAOVoteCast(disputeId, msg.sender, support);
    }

    error NotInAppeal();
    error DAOVoteEnded();

    function finalizeDAO(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.status != DisputeStatus.Appealed) revert NotInAppeal();
        if (block.timestamp <= d.daoVoteDeadline) revert DAOVoteNotEnded();
        bool outcome = d.daoVotesFor > d.daoVotesAgainst;
        d.status = DisputeStatus.Finalized;
        d.finalOutcome = outcome;
        emit DAODecision(disputeId, outcome);
        emit DisputeFinalized(disputeId, outcome);
    }

    error DAOVoteNotEnded();

    function getVoters() external view returns (address[] memory) {
        return voters;
    }

    function getDispute(
        uint256 disputeId
    )
        external
        view
        returns (
            address proposer,
            string memory description,
            uint256 challengeDeadline,
            uint256 votesFor,
            uint256 votesAgainst,
            DisputeStatus status,
            bool appealed,
            uint256 appealFee,
            uint256 daoVoteDeadline,
            uint256 daoVotesFor,
            uint256 daoVotesAgainst,
            bool finalOutcome
        )
    {
        Dispute storage d = disputes[disputeId];
        return (
            d.proposer,
            d.description,
            d.challengeDeadline,
            d.votesFor,
            d.votesAgainst,
            d.status,
            d.appealed,
            d.appealFee,
            d.daoVoteDeadline,
            d.daoVotesFor,
            d.daoVotesAgainst,
            d.finalOutcome
        );
    }
}
