// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IReputationSBT {
    function updateRentalHistory(
        address user,
        IERC20 currency,
        uint256 amount,
        bool successful
    ) external;

    function getReputationScore(address user) external view returns (uint256);
}

interface IMultiCurrencyRiskVault {
    function lockBuffer(
        uint256 escrowId,
        IERC20 currency,
        uint256 amount,
        uint256 duration,
        address escrowAddress
    ) external returns (uint256 lockId);

    function releaseBuffer(uint256 lockId) external;

    function claimBuffer(
        uint256 lockId,
        address recipient,
        uint256 amount
    ) external;
}

contract MultiCurrencyRentEscrow is
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // =========================
    // ROLES
    // =========================
    bytes32 public constant DISPUTE_RESOLVER_ROLE =
        keccak256("DISPUTE_RESOLVER_ROLE");

    // =========================
    // IMMUTABLES (gas + security)
    // =========================
    IERC20 public immutable USDC;
    IERC20 public immutable EURC;
    IReputationSBT public immutable reputation;
    IMultiCurrencyRiskVault public immutable riskBufferVault;

    // =========================
    // STATE
    // =========================
    enum EscrowStatus {
        None,
        Active,
        Disputed,
        TenantReleased,
        LandlordReleased,
        Cancelled,
        Resolved
    }

    enum DisputeOutcome {
        Pending,
        TenantFavor,
        LandlordFavor,
        Split
    }

    // =========================
    // ESCROW STORAGE
    // =========================
    struct EscrowDetails {
        address tenant;
        address landlord;

        IERC20 currency;

        uint96 depositAmount;
        uint96 monthlyRent;
        uint96 damageThreshold;

        uint64 startTime;
        uint64 endTime;
        uint64 nextRentDue;

        EscrowStatus status;

        bool autoRelease;
        bool requireInspection;

        uint256 riskBufferLockId;
        bool rentSettled;
        bool finalized;
    }

    struct DisputeDetails {
        uint256 escrowId;
        address initiator;
        IERC20 currency;
        uint256 claimedAmount;
        uint256 timestamp;

        DisputeOutcome outcome;
        bool resolved;
    }

    // =========================
    // STORAGE
    // =========================
    mapping(uint256 => EscrowDetails) public escrows;
    mapping(uint256 => DisputeDetails) public disputes;

    uint256 public nextDisputeId = 1;

    uint256 public usdcToEurcRate = 92e16;

    // =========================
    // EVENTS
    // =========================
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed tenant,
        address indexed landlord,
        IERC20 currency,
        uint256 depositAmount
    );

    event RentReleased(
        uint256 indexed escrowId,
        uint256 amount,
        IERC20 currency
    );

    event DisputeCreated(
        uint256 indexed disputeId,
        uint256 indexed escrowId,
        address indexed initiator
    );

    event ExchangeRateUpdated(uint256 newRate);

    event EscrowFinalized(uint256 indexed escrowId);

    // =========================
    // ERRORS
    // =========================
    error InvalidLandlord();
    error InvalidCurrency();
    error InvalidState();
    error Unauthorized();
    error AlreadyExists();
    error NotDue();
    error AlreadyFinalized();
    error TransferFailed();

    // =========================
    // CONSTRUCTOR
    // =========================
    constructor(
        address _usdc,
        address _eurc,
        address _reputation,
        address _riskVault
    ) {
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        reputation = IReputationSBT(_reputation);
        riskBufferVault = IMultiCurrencyRiskVault(_riskVault);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }

    // =========================
    // CREATE ESCROW (HARDENED)
    // =========================
    function createEscrow(
        address landlord,
        IERC20 currency,
        uint96 depositAmount,
        uint96 monthlyRent,
        uint96 damageThreshold,
        uint64 leaseDuration,
        bool autoRelease,
        bool requireInspection,
        string calldata propertyDetails
    ) external whenNotPaused nonReentrant returns (uint256 escrowId) {
        if (landlord == address(0) || landlord == msg.sender)
            revert InvalidLandlord();

        if (currency != USDC && currency != EURC) revert InvalidCurrency();

        escrowId = uint256(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    landlord,
                    block.timestamp,
                    propertyDetails
                )
            )
        );

        if (escrows[escrowId].tenant != address(0)) revert AlreadyExists();

        EscrowDetails storage e = escrows[escrowId];

        e.tenant = msg.sender;
        e.landlord = landlord;
        e.currency = currency;

        e.depositAmount = depositAmount;
        e.monthlyRent = monthlyRent;
        e.damageThreshold = damageThreshold;

        e.startTime = uint64(block.timestamp);
        e.endTime = uint64(block.timestamp + leaseDuration);
        e.nextRentDue = uint64(block.timestamp + 30 days);

        e.status = EscrowStatus.Active;
        e.autoRelease = autoRelease;
        e.requireInspection = requireInspection;

        // risk buffer MUST succeed
        e.riskBufferLockId = riskBufferVault.lockBuffer(
            escrowId,
            currency,
            (uint256(depositAmount) * 10) / 100,
            leaseDuration,
            address(this)
        );

        emit EscrowCreated(
            escrowId,
            msg.sender,
            landlord,
            currency,
            depositAmount
        );
    }

    // =========================
    // RENT RELEASE (HARDENED)
    // =========================
    function releaseRent(uint256 escrowId)
        external
        whenNotPaused
        nonReentrant
    {
        EscrowDetails storage e = escrows[escrowId];

        if (e.status != EscrowStatus.Active) revert InvalidState();
        if (e.finalized) revert AlreadyFinalized();
        if (block.timestamp < e.nextRentDue) revert NotDue();

        // only tenant/landlord/admin
        if (
            msg.sender != e.tenant &&
            msg.sender != e.landlord &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) revert Unauthorized();

        e.nextRentDue += 30 days;

        uint256 amount = uint256(e.monthlyRent);

        e.currency.safeTransfer(e.landlord, amount);

        reputation.updateRentalHistory(
            e.tenant,
            e.currency,
            amount,
            true
        );

        emit RentReleased(escrowId, amount, e.currency);
    }

    // =========================
    // DISPUTE INIT
    // =========================
    function createDispute(uint256 escrowId)
        external
        whenNotPaused
        nonReentrant
    {
        EscrowDetails storage e = escrows[escrowId];

        if (e.status != EscrowStatus.Active) revert InvalidState();

        e.status = EscrowStatus.Disputed;

        uint256 disputeId = nextDisputeId++;

        disputes[disputeId] = DisputeDetails({
            escrowId: escrowId,
            initiator: msg.sender,
            currency: e.currency,
            claimedAmount: uint256(e.depositAmount),
            timestamp: block.timestamp,
            outcome: DisputeOutcome.Pending,
            resolved: false
        });

        emit DisputeCreated(disputeId, escrowId, msg.sender);
    }

    // =========================
    // ADMIN
    // =========================
    function updateExchangeRate(uint256 newRate)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        usdcToEurcRate = newRate;
        emit ExchangeRateUpdated(newRate);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}