// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract DisputeResolutionDAO is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ----------------------------
    // Roles
    // ----------------------------
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MEMBER_ROLE   = keccak256("MEMBER_ROLE");
    bytes32 public constant ESCROW_ROLE   = keccak256("ESCROW_ROLE"); // approved escrows/factories

    // ----------------------------
    // Governance params
    // ----------------------------
    uint256 public votingPeriod;   // e.g. 7 days
    uint256 public quorum;         // minimum votes required to resolve
    uint256 public maxAppeals;     // e.g. 1

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
        uint256 totalVotes;

        bool resolved;
        uint8 appealCount;
    }

    uint256 public disputeCount;
    mapping(uint256 => Dispute) private _disputes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event DisputeCreated(uint256 indexed disputeId, address indexed escrow, address renter, address landlord, uint256 depositAmount);
    event Voted(uint256 indexed disputeId, address indexed voter, Outcome outcome);
    event DisputeResolved(uint256 indexed disputeId, Outcome outcome, uint256 totalVotes);
    event AppealRequested(uint256 indexed disputeId, uint8 appealCount);

    error InvalidDispute();
    error NotEscrow();
    error NotMember();
    error VotingEnded();
    error VotingNotEnded();
    error AlreadyResolved();
    error AlreadyVoted();
    error InvalidOutcome();
    error QuorumNotMet();
    error AppealNotAllowed();
    error Unauthorized();

    // ----------------------------
    // Upgradeability
    // ----------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ----------------------------
    // Initializer
    // ----------------------------
    function initialize(
        address admin,
        uint256 _votingPeriod,
        uint256 _quorum,
        uint256 _maxAppeals
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(admin != address(0), "admin=0");
        require(_votingPeriod > 0, "votingPeriod=0");

        votingPeriod = _votingPeriod;
        quorum = _quorum;
        maxAppeals = _maxAppeals;

        // Admin gets all powers initially
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ----------------------------
    // Admin config
    // ----------------------------
    function setVotingPeriod(uint256 _votingPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_votingPeriod > 0, "votingPeriod=0");
        votingPeriod = _votingPeriod;
    }

    function setQuorum(uint256 _quorum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        quorum = _quorum;
    }

    function setMaxAppeals(uint256 _maxAppeals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxAppeals = _maxAppeals;
    }

    // ----------------------------
    // Read helpers
    // ----------------------------
    function getDispute(uint256 disputeId) external view returns (Dispute memory) {
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();
        return _disputes[disputeId];
    }

    function getOutcome(uint256 disputeId) external view returns (Outcome outcome, bool resolved) {
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();
        Dispute storage d = _disputes[disputeId];
        return (d.outcome, d.resolved);
    }

    function isVotingOpen(uint256 disputeId) external view returns (bool) {
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();
        Dispute storage d = _disputes[disputeId];
        return block.timestamp <= d.createdAt + votingPeriod && !d.resolved;
    }

    // ----------------------------
    // Core actions
    // ----------------------------

    /// @notice Only approved escrows (or escrow factories) can open disputes.
    function createDispute(
        address escrow,
        address renter,
        address landlord,
        uint256 depositAmount
    ) external returns (uint256) {
        if (!hasRole(ESCROW_ROLE, msg.sender)) revert NotEscrow();
        require(escrow != address(0) && renter != address(0) && landlord != address(0), "addr=0");

        disputeCount++;
        _disputes[disputeCount] = Dispute({
            escrow: escrow,
            renter: renter,
            landlord: landlord,
            depositAmount: depositAmount,
            createdAt: block.timestamp,

            outcome: Outcome.None,
            votesFull: 0,
            votesPartial: 0,
            votesNone: 0,
            totalVotes: 0,

            resolved: false,
            appealCount: 0
        });

        emit DisputeCreated(disputeCount, escrow, renter, landlord, depositAmount);
        return disputeCount;
    }

    function vote(uint256 disputeId, Outcome outcome) external {
        if (!hasRole(MEMBER_ROLE, msg.sender)) revert NotMember();
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();

        Dispute storage d = _disputes[disputeId];
        if (d.resolved) revert AlreadyResolved();
        if (block.timestamp > d.createdAt + votingPeriod) revert VotingEnded();
        if (hasVoted[disputeId][msg.sender]) revert AlreadyVoted();
        if (outcome == Outcome.None) revert InvalidOutcome();

        hasVoted[disputeId][msg.sender] = true;

        unchecked {
            d.totalVotes++;
            if (outcome == Outcome.FullRefund) d.votesFull++;
            else if (outcome == Outcome.PartialRefund) d.votesPartial++;
            else d.votesNone++;
        }

        emit Voted(disputeId, msg.sender, outcome);
    }

    function resolveDispute(uint256 disputeId) external {
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();

        Dispute storage d = _disputes[disputeId];
        if (d.resolved) revert AlreadyResolved();
        if (block.timestamp <= d.createdAt + votingPeriod) revert VotingNotEnded();

        // Quorum check (optional but strongly recommended)
        if (quorum > 0 && d.totalVotes < quorum) revert QuorumNotMet();

        d.resolved = true;

        // Deterministic tie-break policy:
        // - Choose the highest vote count
        // - If tied, fall back to PartialRefund (middle-ground) rather than defaulting to FullRefund.
        uint256 full = d.votesFull;
        uint256 part = d.votesPartial;
        uint256 none = d.votesNone;

        if (part >= full && part >= none) {
            d.outcome = Outcome.PartialRefund;
        } else if (full >= part && full >= none) {
            d.outcome = Outcome.FullRefund;
        } else {
            d.outcome = Outcome.NoRefund;
        }

        emit DisputeResolved(disputeId, d.outcome, d.totalVotes);
    }

    function requestAppeal(uint256 disputeId) external {
        if (disputeId == 0 || disputeId > disputeCount) revert InvalidDispute();

        Dispute storage d = _disputes[disputeId];
        if (!d.resolved) revert VotingNotEnded();
        if (msg.sender != d.renter && msg.sender != d.landlord) revert Unauthorized();
        if (d.appealCount >= maxAppeals) revert AppealNotAllowed();

        // reset vote state for a new round
        d.appealCount++;
        d.resolved = false;
        d.createdAt = block.timestamp;

        d.outcome = Outcome.None;
        d.votesFull = 0;
        d.votesPartial = 0;
        d.votesNone = 0;
        d.totalVotes = 0;

        emit AppealRequested(disputeId, d.appealCount);
    }

    // storage gap for upgrade safety
    uint256[45] private __gap;
}
