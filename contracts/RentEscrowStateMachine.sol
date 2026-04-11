// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {DisputeResolutionDAO} from "./DisputeResolutionDAO.sol";

contract RentEscrowStateMachine is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // =========================
    // ROLES
    // =========================
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // =========================
    // STATE MACHINE
    // =========================
    enum State {
        Initialized,
        DepositPaid,
        RentPaid,
        Disputed,
        Completed,
        Refunded
    }

    enum RefundType {
        None,
        Full,
        Partial
    }

    // =========================
    // STORAGE
    // =========================
    address public renter;
    address public landlord;

    uint256 public depositAmount;
    uint256 public rentAmount;

    uint256 public depositPaid;
    uint256 public rentPaid;

    State public state;
    RefundType public refundType;

    DisputeResolutionDAO public dao;
    uint256 public disputeId;

    bool public disputeFinalized;
    bool public payoutExecuted;
    bool public disputeActive;

    uint256 public lastDisputeTime;
    uint256 public constant DISPUTE_COOLDOWN = 1 days;

    // =========================
    // EVENTS
    // =========================
    event DepositReceived(address indexed renter, uint256 amount);
    event RentReceived(address indexed renter, uint256 amount);
    event StateChanged(State newState);

    event DisputeRaised(uint256 indexed disputeId);
    event DisputeOutcomeApplied(uint256 indexed disputeId, RefundType outcome);

    // =========================
    // ERRORS
    // =========================
    error NotRenter();
    error NotLandlord();
    error InvalidState();
    error InvalidAddress();
    error IncorrectDeposit();
    error IncorrectRent();
    error DaoNotSet();
    error CooldownActive();
    error DisputeAlreadyFinalized();
    error PayoutAlreadyExecuted();
    error DisputeNotResolved();
    error Unauthorized();

    // =========================
    // MODIFIERS
    // =========================
    modifier onlyRenter() {
        if (msg.sender != renter) revert NotRenter();
        _;
    }

    modifier onlyLandlord() {
        if (msg.sender != landlord) revert NotLandlord();
        _;
    }

    modifier inState(State s) {
        if (state != s) revert InvalidState();
        _;
    }

    // =========================
    // UUPS AUTH
    // =========================
    function _authorizeUpgrade(address)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    // =========================
    // INIT
    // =========================
    function initialize(
        address _renter,
        address _landlord,
        uint256 _depositAmount,
        uint256 _rentAmount,
        address _dao,
        address admin
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (
            _renter == address(0) ||
            _landlord == address(0) ||
            _dao == address(0) ||
            admin == address(0)
        ) revert InvalidAddress();

        renter = _renter;
        landlord = _landlord;
        depositAmount = _depositAmount;
        rentAmount = _rentAmount;
        dao = DisputeResolutionDAO(_dao);

        state = State.Initialized;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // =========================
    // PAYMENTS
    // =========================
    function payDeposit()
        external
        payable
        onlyRenter
        inState(State.Initialized)
        nonReentrant
    {
        if (msg.value != depositAmount) revert IncorrectDeposit();

        depositPaid = msg.value;
        state = State.DepositPaid;

        emit DepositReceived(msg.sender, msg.value);
        emit StateChanged(state);
    }

    function payRent()
        external
        payable
        onlyRenter
        inState(State.DepositPaid)
        nonReentrant
    {
        if (msg.value != rentAmount) revert IncorrectRent();

        rentPaid = msg.value;
        state = State.RentPaid;

        emit RentReceived(msg.sender, msg.value);
        emit StateChanged(state);
    }

    // =========================
    // DISPUTE CREATION (HARDENED)
    // =========================
    function raiseDispute()
        external
        nonReentrant
    {
        if (msg.sender != renter && msg.sender != landlord) revert Unauthorized();
        if (address(dao) == address(0)) revert DaoNotSet();
        if (state != State.RentPaid) revert InvalidState();
        if (block.timestamp < lastDisputeTime + DISPUTE_COOLDOWN) revert CooldownActive();

        state = State.Disputed;
        disputeActive = true;
        disputeFinalized = false;
        payoutExecuted = false;

        lastDisputeTime = block.timestamp;

        disputeId = dao.createDispute(
            address(this),
            renter,
            landlord,
            depositAmount
        );

        emit DisputeRaised(disputeId);
        emit StateChanged(state);
    }

    // =========================
    // APPLY DAO RESULT (CRITICAL PATH)
    // =========================
    function applyDisputeOutcome()
        external
        nonReentrant
        inState(State.Disputed)
    {
        if (disputeFinalized) revert DisputeAlreadyFinalized();
        if (payoutExecuted) revert PayoutAlreadyExecuted();

        (DisputeResolutionDAO.Outcome outcome, bool resolved) =
            dao.getOutcome(disputeId);

        if (!resolved) revert DisputeNotResolved();

        disputeFinalized = true;
        payoutExecuted = true;

        uint256 total = depositPaid + rentPaid;

        if (outcome == DisputeResolutionDAO.Outcome.FullRefund) {
            refundType = RefundType.Full;
            state = State.Refunded;

            _payout(renter, total);
        }
        else if (outcome == DisputeResolutionDAO.Outcome.PartialRefund) {
            refundType = RefundType.Partial;
            state = State.Refunded;

            uint256 renterShare = (total * 50) / 100;

            _payout(renter, renterShare);
            _payout(landlord, total - renterShare);
        }
        else {
            refundType = RefundType.None;
            state = State.Completed;

            _payout(landlord, total);
        }

        emit DisputeOutcomeApplied(disputeId, refundType);
        emit StateChanged(state);
    }

    // =========================
    // INTERNAL PAYOUT
    // =========================
    function _payout(address to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "TRANSFER_FAILED");
    }

    // =========================
    // ETH SAFETY
    // =========================
    receive() external payable {
        revert("ETH_NOT_ACCEPTED");
    }

    uint256[48] private __gap;
}