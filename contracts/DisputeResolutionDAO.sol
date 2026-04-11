// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract DisputeResolutionDAO is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    // =============================
    // ROLES
    // =============================
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MEMBER_ROLE   = keccak256("MEMBER_ROLE");
    bytes32 public constant ESCROW_ROLE   = keccak256("ESCROW_ROLE");

    // =============================
    // CONFIG
    // =============================
    uint256 public votingPeriod;
    uint256 public quorum;
    uint256 public maxAppeals;

    // =============================
    // OUTCOME
    // =============================
    enum Outcome {
        None,
        FullRefund,
        PartialRefund,
        NoRefund
    }

    enum Status {
        Active,
        VotingEnded,
        Resolved,
        Finalized,
        Appealed
    }

    // =============================
    // DISPUTE
    // =============================
    struct Dispute {
        address escrow;
        address renter;
        address landlord;
        uint256 depositAmount;

        uint256 createdAt;

        uint256 votesFull;
        uint256 votesPartial;
        uint256 votesNone;
        uint256 totalVotes;

        Outcome outcome;
        Status status;

        uint8 appealCount;

        bool exists;
    }

    // =============================
    // STORAGE
    // =============================
    uint256 public disputeCount;

    mapping(uint256 => Dispute) private disputes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // SINGLE SOURCE OF TRUTH (CRITICAL FIX)
    mapping(uint256 => bool) public finalized;
    mapping(uint256 => Outcome) public finalOutcome;

    // =============================
    // EVENTS
    // =============================
    event DisputeCreated(uint256 indexed disputeId, address indexed escrow);
    event Voted(uint256 indexed disputeId, address voter, Outcome vote);
    event DisputeResolved(uint256 indexed disputeId, Outcome outcome);
    event DisputeFinalized(uint256 indexed disputeId, Outcome outcome);
    event AppealRequested(uint256 indexed disputeId, uint8 appealCount);

    // =============================
    // ERRORS
    // =============================
    error InvalidDispute();
    error NotMember();
    error VotingClosed();
    error AlreadyVoted();
    error AlreadyFinalized();
    error NotResolved();
    error QuorumNotMet();
    error Unauthorized();
    error AppealLimitReached();
    error InvalidOutcome();

    // =============================
    // UUPS
    // =============================
    function _authorizeUpgrade(address)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    // =============================
    // INIT
    // =============================
    function initialize(
        address admin,
        uint256 _votingPeriod,
        uint256 _quorum,
        uint256 _maxAppeals
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        votingPeriod = _votingPeriod;
        quorum = _quorum;
        maxAppeals = _maxAppeals;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // =============================
    // CREATE DISPUTE
    // =============================
    function createDispute(
        address escrow,
        address renter,
        address landlord,
        uint256 depositAmount
    ) external onlyRole(ESCROW_ROLE) returns (uint256 disputeId) {

        if (
            escrow == address(0) ||
            renter == address(0) ||
            landlord == address(0)
        ) revert InvalidDispute();

        disputeId = ++disputeCount;

        Dispute storage d = disputes[disputeId];

        d.escrow = escrow;
        d.renter = renter;
        d.landlord = landlord;
        d.depositAmount = depositAmount;
        d.createdAt = block.timestamp;
        d.status = Status.Active;
        d.exists = true;
    }

    // =============================
    // VOTING (HARDENED)
    // =============================
    function vote(uint256 disputeId, Outcome choice)
        external
        onlyRole(MEMBER_ROLE)
    {
        Dispute storage d = disputes[disputeId];

        if (!d.exists) revert InvalidDispute();
        if (finalized[disputeId]) revert AlreadyFinalized();
        if (hasVoted[disputeId][msg.sender]) revert AlreadyVoted();
        if (block.timestamp > d.createdAt + votingPeriod) revert VotingClosed();
        if (choice == Outcome.None) revert InvalidOutcome();

        hasVoted[disputeId][msg.sender] = true;

        unchecked {
            d.totalVotes++;
            if (choice == Outcome.FullRefund) d.votesFull++;
            else if (choice == Outcome.PartialRefund) d.votesPartial++;
            else d.votesNone++;
        }

        emit Voted(disputeId, msg.sender, choice);
    }

    // =============================
    // RESOLVE (DETERMINISTIC)
    // =============================
    function resolveDispute(uint256 disputeId) public {
        Dispute storage d = disputes[disputeId];

        if (!d.exists) revert InvalidDispute();
        if (d.status == Status.Resolved) revert AlreadyFinalized();
        if (block.timestamp <= d.createdAt + votingPeriod) revert VotingClosed();
        if (quorum > 0 && d.totalVotes < quorum) revert QuorumNotMet();

        d.status = Status.Resolved;

        if (
            d.votesPartial >= d.votesFull &&
            d.votesPartial >= d.votesNone
        ) {
            d.outcome = Outcome.PartialRefund;
        } else if (
            d.votesFull >= d.votesPartial &&
            d.votesFull >= d.votesNone
        ) {
            d.outcome = Outcome.FullRefund;
        } else {
            d.outcome = Outcome.NoRefund;
        }

        emit DisputeResolved(disputeId, d.outcome);
    }

    // =============================
    // FINALIZATION (CRITICAL SAFETY LAYER)
    // =============================
    function finalizeDispute(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];

        if (!d.exists) revert InvalidDispute();
        if (d.status != Status.Resolved) revert NotResolved();
        if (finalized[disputeId]) revert AlreadyFinalized();

        finalized[disputeId] = true;
        finalOutcome[disputeId] = d.outcome;
        d.status = Status.Finalized;

        emit DisputeFinalized(disputeId, d.outcome);
    }

    // =============================
    // VIEW (ESCROW SAFE CONSUMPTION)
    // =============================
    function getOutcome(uint256 disputeId)
        external
        view
        returns (Outcome outcome, bool isFinal)
    {
        return (finalOutcome[disputeId], finalized[disputeId]);
    }

    // =============================
    // APPEALS (SAFE RESET)
    // =============================
    function requestAppeal(uint256 disputeId) external {
        Dispute storage d = disputes[disputeId];

        if (msg.sender != d.renter && msg.sender != d.landlord)
            revert Unauthorized();

        if (!d.exists) revert InvalidDispute();
        if (!finalized[disputeId]) revert NotResolved();
        if (d.appealCount >= maxAppeals) revert AppealLimitReached();

        d.appealCount++;
        d.status = Status.Appealed;

        // reset voting cycle safely
        d.createdAt = block.timestamp;

        d.votesFull = 0;
        d.votesPartial = 0;
        d.votesNone = 0;
        d.totalVotes = 0;

        finalized[disputeId] = false;
        finalOutcome[disputeId] = Outcome.None;

        emit AppealRequested(disputeId, d.appealCount);
    }

    // =============================
    // STORAGE GAP
    // =============================
    uint256[45] private __gap;
}