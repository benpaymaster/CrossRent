// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

contract OptimisticDemocracy {

    // =============================
    // STATE
    // =============================
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
        uint256 daoVoteDeadline;

        uint256 votesFor;
        uint256 votesAgainst;

        uint256 daoVotesFor;
        uint256 daoVotesAgainst;

        bool appealed;
        bool finalOutcome;

        uint256 appealFee;
        DisputeStatus status;

        mapping(address => bool) hasVoted;
        mapping(address => bool) daoHasVoted;
    }

    // =============================
    // STORAGE
    // =============================
    uint256 public disputeCount;
    uint256 public challengePeriod;

    mapping(uint256 => Dispute) private disputes;

    mapping(address => bool) public isVoter;

    uint256 public collectedAppealFees;

    // =============================
    // EVENTS
    // =============================
    event DisputeRaised(uint256 indexed id, address indexed proposer, string description);
    event VoteCast(uint256 indexed id, address indexed voter, bool support);
    event DisputeResolved(uint256 indexed id, bool outcome);
    event DisputeAppealed(uint256 indexed id, address indexed by, uint256 fee);
    event DAOVoteCast(uint256 indexed id, address indexed voter, bool support);
    event DAODecision(uint256 indexed id, bool outcome);
    event DisputeFinalized(uint256 indexed id, bool outcome);

    // =============================
    // ERRORS
    // =============================
    error NotVoter();
    error InvalidStatus();
    error ChallengeEnded();
    error AlreadyVoted();
    error NotResolved();
    error AlreadyAppealed();
    error InsufficientAppealFee();
    error DAOVoteEnded();
    error DAOVoteNotEnded();
    error AlreadyResolved();

    // =============================
    // SECURITY
    // =============================
    bool private locked;

    modifier nonReentrant() {
        require(!locked, "REENTRANCY");
        locked = true;
        _;
        locked = false;
    }

    modifier onlyVoter() {
        if (!isVoter[msg.sender]) revert NotVoter();
        _;
    }

    // =============================
    // INIT
    // =============================
    constructor(address[] memory _voters, uint256 _challengePeriod) {
        challengePeriod = _challengePeriod;

        for (uint256 i = 0; i < _voters.length; i++) {
            isVoter[_voters[i]] = true;
        }
    }

    // =============================
    // DISPUTE CREATION
    // =============================
    function raiseDispute(string calldata description)
        external
        returns (uint256)
    {
        uint256 id = ++disputeCount;

        Dispute storage d = disputes[id];
        d.proposer = msg.sender;
        d.description = description;
        d.challengeDeadline = block.timestamp + challengePeriod;
        d.status = DisputeStatus.Raised;
        d.appealFee = 0.01 ether;

        emit DisputeRaised(id, msg.sender, description);
        return id;
    }

    // =============================
    // VOTING
    // =============================
    function vote(uint256 id, bool support)
        external
        onlyVoter
    {
        Dispute storage d = disputes[id];

        if (d.status != DisputeStatus.Raised && d.status != DisputeStatus.Voting)
            revert InvalidStatus();

        if (block.timestamp > d.challengeDeadline)
            revert ChallengeEnded();

        if (d.hasVoted[msg.sender])
            revert AlreadyVoted();

        d.hasVoted[msg.sender] = true;

        if (support) d.votesFor++;
        else d.votesAgainst++;

        d.status = DisputeStatus.Voting;

        emit VoteCast(id, msg.sender, support);
    }

    // =============================
    // RESOLVE
    // =============================
    function finalize(uint256 id) external {
        Dispute storage d = disputes[id];

        if (block.timestamp <= d.challengeDeadline)
            revert ChallengeEnded();

        if (d.status != DisputeStatus.Raised && d.status != DisputeStatus.Voting)
            revert InvalidStatus();

        bool outcome = d.votesFor > d.votesAgainst;

        d.status = DisputeStatus.Resolved;
        d.finalOutcome = outcome;

        emit DisputeResolved(id, outcome);
    }

    // =============================
    // APPEAL (HARDENED)
    // =============================
    function appeal(uint256 id)
        external
        payable
        nonReentrant
    {
        Dispute storage d = disputes[id];

        if (d.status != DisputeStatus.Resolved)
            revert NotResolved();

        if (d.appealed)
            revert AlreadyAppealed();

        if (msg.value < d.appealFee)
            revert InsufficientAppealFee();

        d.appealed = true;
        d.status = DisputeStatus.Appealed;
        d.daoVoteDeadline = block.timestamp + 7 days;

        collectedAppealFees += msg.value;

        emit DisputeAppealed(id, msg.sender, msg.value);
    }

    // =============================
    // DAO VOTING
    // =============================
    function daoVote(uint256 id, bool support)
        external
        onlyVoter
    {
        Dispute storage d = disputes[id];

        if (d.status != DisputeStatus.Appealed)
            revert InvalidStatus();

        if (block.timestamp > d.daoVoteDeadline)
            revert DAOVoteEnded();

        if (d.daoHasVoted[msg.sender])
            revert AlreadyVoted();

        d.daoHasVoted[msg.sender] = true;

        if (support) d.daoVotesFor++;
        else d.daoVotesAgainst++;

        emit DAOVoteCast(id, msg.sender, support);
    }

    // =============================
    // FINAL DAO DECISION
    // =============================
    function finalizeDAO(uint256 id) external {
        Dispute storage d = disputes[id];

        if (d.status != DisputeStatus.Appealed)
            revert InvalidStatus();

        if (block.timestamp <= d.daoVoteDeadline)
            revert DAOVoteNotEnded();

        bool outcome = d.daoVotesFor > d.daoVotesAgainst;

        d.status = DisputeStatus.Finalized;
        d.finalOutcome = outcome;

        emit DAODecision(id, outcome);
        emit DisputeFinalized(id, outcome);
    }

    // =============================
    // ADMIN (FEES RECOVERY)
    // =============================
    function withdrawFees(address payable to) external {
        require(msg.sender == to, "only self withdrawal");
        uint256 amount = collectedAppealFees;
        collectedAppealFees = 0;

        (bool ok,) = to.call{value: amount}("");
        require(ok, "TRANSFER_FAILED");
    }

    // =============================
    // VIEW
    // =============================
    function getVoters() external view returns (address[] memory) {
        // not enumerable anymore (fixes DoS risk)
        revert("not supported - use isVoter mapping");
    }

    function getDispute(uint256 id)
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
        Dispute storage d = disputes[id];

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

    // =============================
    // RECEIVE SAFETY
    // =============================
    receive() external payable {}
}