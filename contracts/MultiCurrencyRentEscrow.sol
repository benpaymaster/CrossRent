// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IReputationSBT {
    function updateRentalHistory(address user, IERC20 currency, uint256 amount, bool successful) external;
    function getReputationScore(address user) external view returns (uint256);
}

interface IMultiCurrencyRiskVault {
    function lockBuffer(uint256 escrowId, IERC20 currency, uint256 amount, uint256 duration, address escrowAddress) external returns (uint256 lockId);
    function releaseBuffer(uint256 lockId) external;
    function claimBuffer(uint256 lockId, address recipient, uint256 amount) external;
}

contract MultiCurrencyRentEscrow is AccessControlEnumerable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    IERC20 public immutable USDC;
    IERC20 public immutable EURC;
    IReputationSBT public reputation;
    IMultiCurrencyRiskVault public riskBufferVault;

    enum EscrowStatus { None, Active, TenantReleased, LandlordReleased, Disputed, Resolved, Cancelled }
    enum DisputeOutcome { Pending, TenantFavor, LandlordFavor, Split }

    // MONAD OPTIMIZATION: Packed Struct (Reduces SSTORE from 12+ slots to 5)
    struct EscrowDetails {
        address tenant;              // Slot 0
        EscrowStatus status;         // Slot 0 (1 byte)
        address landlord;            // Slot 1
        uint64 startTime;            // Slot 1 (8 bytes)
        uint64 endTime;              // Slot 2 (8 bytes)
        uint64 nextRentDue;          // Slot 2 (8 bytes)
        uint96 monthlyRent;          // Slot 2 (12 bytes)
        uint96 depositAmount;        // Slot 3 (12 bytes)
        uint96 damageThreshold;      // Slot 3 (12 bytes)
        bool autoRelease;            // Slot 3 (1 byte)
        bool requireInspection;      // Slot 3 (1 byte)
        bool requireTenantConfirmation; // Slot 3 (1 byte)
        IERC20 currency;             // Slot 4
        uint256 riskBufferLockId;    // Slot 5
    }

    struct DisputeDetails {
        uint256 escrowId;
        address initiator;
        uint256 claimedAmount;
        IERC20 currency;
        uint256 timestamp;
        DisputeOutcome outcome;
        bool resolved;
    }

    // MONAD OPTIMIZATION: Using uint256(keccak256) as keys for Parallel Execution
    mapping(uint256 => EscrowDetails) public escrows;
    mapping(uint256 => DisputeDetails) public disputes;
    
    // Global counters are now used ONLY for Disputes (Lower frequency than Escrows)
    uint256 public nextDisputeId = 1;
    uint256 public usdcToEurcRate = 92e16; 

    event EscrowCreated(uint256 indexed escrowId, address indexed tenant, address indexed landlord, IERC20 currency, uint256 depositAmount);
    event RentReleased(uint256 indexed escrowId, uint256 amount, IERC20 currency);
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed escrowId, address indexed initiator);
    event ExchangeRateUpdated(uint256 newRate);

    constructor(address _usdc, address _eurc, address _reputation, address _riskBufferVault) {
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        reputation = IReputationSBT(_reputation);
        riskBufferVault = IMultiCurrencyRiskVault(_riskBufferVault);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }

    /**
     * @dev Create escrow using Deterministic IDs to enable Parallel Monad Execution
     */
    function createEscrow(
        address landlord,
        IERC20 currency,
        uint96 depositAmount,
        uint96 monthlyRent,
        uint96 damageThreshold,
        uint64 leaseDuration,
        bool autoRelease,
        bool requireInspection,
        string calldata propertyDetails // Emitted, not stored, to save MonadDB I/O
    ) external whenNotPaused nonReentrant returns (uint256 escrowId) {
        require(landlord != address(0) && landlord != msg.sender, "Invalid landlord");
        require(currency == USDC || currency == EURC, "Unsupported currency");

        // MONAD OPTIMIZATION: Deterministic ID prevents state contention on a global counter
        escrowId = uint256(keccak256(abi.encodePacked(msg.sender, landlord, block.timestamp, propertyDetails)));
        require(escrows[escrowId].tenant == address(0), "Collision");

        currency.safeTransferFrom(msg.sender, address(this), uint256(depositAmount));

        uint256 lockId = riskBufferVault.lockBuffer(
            escrowId,
            currency,
            (uint256(depositAmount) * 10) / 100,
            uint256(leaseDuration),
            address(this)
        );

        escrows[escrowId] = EscrowDetails({
            tenant: msg.sender,
            landlord: landlord,
            currency: currency,
            depositAmount: depositAmount,
            monthlyRent: monthlyRent,
            damageThreshold: damageThreshold,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp) + leaseDuration,
            nextRentDue: uint64(block.timestamp) + 30 days,
            status: EscrowStatus.Active,
            autoRelease: autoRelease,
            requireInspection: requireInspection,
            requireTenantConfirmation: true,
            riskBufferLockId: lockId
        });

        emit EscrowCreated(escrowId, msg.sender, landlord, currency, uint256(depositAmount));
    }

    function releaseRent(uint256 escrowId) external whenNotPaused nonReentrant {
        EscrowDetails storage escrow = escrows[escrowId];
        require(escrow.status == EscrowStatus.Active, "Not active");
        require(msg.sender == escrow.landlord || msg.sender == escrow.tenant || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Auth");
        require(block.timestamp >= escrow.nextRentDue, "Early");

        uint256 amount = uint256(escrow.monthlyRent);
        escrow.nextRentDue += 30 days;
        escrow.currency.safeTransfer(escrow.landlord, amount);

        reputation.updateRentalHistory(escrow.tenant, escrow.currency, amount, true);
        emit RentReleased(escrowId, amount, escrow.currency);
    }

    // Minimal helper for currency parity
    function updateExchangeRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdcToEurcRate = newRate;
        emit ExchangeRateUpdated(newRate);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}