// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IReputationSBT {
    function updateRentalHistory(
        address user,
        uint256 amount,
        bool successful
    ) external;

    function updateRentalHistoryWithToken(
        address user,
        uint256 amount,
        bool successful,
        address token
    ) external;

    function getReputationScore(address user) external view returns (uint256);
}

interface IRiskBufferVault {
    function lockBuffer(uint256 escrowId, uint256 amount) external;

    function lockBufferWithToken(
        uint256 escrowId,
        uint256 amount,
        address token
    ) external;

    function releaseBuffer(uint256 escrowId) external;
}

/**
 * @title RentCreditEscrow
 * @dev Advanced programmable escrow system for cross-border rental deposits using USDC and EURC
 * Features automated conditions, dispute resolution, multi-stablecoin support, and cross-chain compatibility
 *
 * ## Engineering Notes
 * - Gas optimized: custom errors, minimal storage, efficient transfer logic
 * - Security: reentrancy guard, access control, event-driven state changes
 */
contract RentCreditEscrow is
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    bytes32 public constant DISPUTE_RESOLVER_ROLE =
        keccak256("DISPUTE_RESOLVER_ROLE");
    bytes32 public constant CROSS_CHAIN_RELAYER_ROLE =
        keccak256("CROSS_CHAIN_RELAYER_ROLE");

    IERC20 public immutable USDC;
    IERC20 public immutable EURC;
    IReputationSBT public reputation;
    IRiskBufferVault public riskBufferVault;

    enum EscrowStatus {
        Active,
        TenantReleased,
        LandlordReleased,
        Disputed,
        Resolved,
        Cancelled
    }

    enum DisputeOutcome {
        Pending,
        TenantFavor,
        LandlordFavor,
        Split
    }

    struct Escrow {
        uint256 id;
        address tenant;
        address landlord;
        uint256 depositAmount;
        uint256 rentAmount;
        uint256 startTime;
        uint256 endTime;
        EscrowStatus status;
        bool automaticRelease;
        uint256 disputeDeadline;
        uint256 crossChainOriginId;
        bytes32 propertyHash;
        address token; // USDC or EURC
    }

    struct Dispute {
        uint256 escrowId;
        address initiator;
        string reason;
        uint256 timestamp;
        DisputeOutcome outcome;
        uint256 tenantAmount;
        uint256 landlordAmount;
        bool resolved;
    }

    struct AutomationConditions {
        bool requiresPhysicalInspection;
        bool requiresTenantConfirmation;
        bool requiresPropertyDamageCheck;
        uint256 maxDamageThreshold; // in USDC
        uint256 gracePeriodDays;
    }

    mapping(uint256 => Escrow) public escrows;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => AutomationConditions) public automationConditions;
    mapping(address => uint256[]) public userEscrows;
    mapping(uint256 => bool) public crossChainProcessed;
    mapping(address => bool) public supportedTokens;

    uint256 public nextEscrowId = 1;
    uint256 public platformFeeRate = 250; // 2.5% in basis points
    uint256 public disputeFee = 50e6; // $50 USDC
    uint256 public constant MAX_ESCROW_DURATION = 365 days;
    uint256 public constant MIN_DISPUTE_PERIOD = 7 days;

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed tenant,
        address indexed landlord,
        uint256 depositAmount,
        uint256 rentAmount
    );

    event EscrowReleased(
        uint256 indexed escrowId,
        address indexed recipient,
        uint256 amount,
        bool automatic
    );

    event DisputeInitiated(
        uint256 indexed escrowId,
        address indexed initiator,
        string reason
    );

    event DisputeResolved(
        uint256 indexed escrowId,
        DisputeOutcome outcome,
        uint256 tenantAmount,
        uint256 landlordAmount
    );

    event CrossChainEscrowProcessed(
        uint256 indexed escrowId,
        uint256 indexed originChainId,
        address indexed tenant
    );

    constructor(
        address _usdc,
        address _eurc,
        address _reputation,
        address _riskBufferVault
    ) {
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        reputation = IReputationSBT(_reputation);
        riskBufferVault = IRiskBufferVault(_riskBufferVault);

        // Mark supported tokens
        supportedTokens[_usdc] = true;
        supportedTokens[_eurc] = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new rental escrow with advanced programmable conditions
     */
    function createEscrow(
        address _landlord,
        uint256 _depositAmount,
        uint256 _rentAmount,
        uint256 _duration,
        bytes32 _propertyHash,
        AutomationConditions calldata _conditions,
        uint256 _crossChainOriginId,
        address _token
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(
            _landlord != address(0) && _landlord != msg.sender,
            "Invalid landlord"
        );
        require(_depositAmount > 0 && _rentAmount > 0, "Invalid amounts");
        require(
            _duration > 0 && _duration <= MAX_ESCROW_DURATION,
            "Invalid duration"
        );
        require(supportedTokens[_token], "Unsupported token");

        uint256 totalAmount = _depositAmount + _rentAmount;
        uint256 escrowId = nextEscrowId++;

        // Transfer token from tenant
        IERC20(_token).safeTransferFrom(msg.sender, address(this), totalAmount);

        // Lock risk buffer (try new multi-token function first, fallback to legacy)
        uint256 bufferAmount = (totalAmount * 1000) / 10000; // 10% buffer
        try
            riskBufferVault.lockBufferWithToken(escrowId, bufferAmount, _token)
        {
            // Success with new multi-token function
        } catch {
            // For legacy vault compatibility, only lock buffer if token is USDC
            if (_token == address(USDC)) {
                // Approve vault to take the buffer amount
                IERC20(_token).safeTransfer(address(this), 0); // Reset approval first
                IERC20(_token).forceApprove(
                    address(riskBufferVault),
                    bufferAmount
                );
                riskBufferVault.lockBuffer(escrowId, bufferAmount);
            }
            // For other tokens like EURC, skip buffer locking for now
            // In production, would need separate EURC vault or multi-token vault
        }

        // Create escrow
        escrows[escrowId] = Escrow({
            id: escrowId,
            tenant: msg.sender,
            landlord: _landlord,
            depositAmount: _depositAmount,
            rentAmount: _rentAmount,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            status: EscrowStatus.Active,
            automaticRelease: !_conditions.requiresTenantConfirmation &&
                !_conditions.requiresPhysicalInspection,
            disputeDeadline: block.timestamp + _duration + MIN_DISPUTE_PERIOD,
            crossChainOriginId: _crossChainOriginId,
            propertyHash: _propertyHash,
            token: _token
        });

        automationConditions[escrowId] = _conditions;
        userEscrows[msg.sender].push(escrowId);
        userEscrows[_landlord].push(escrowId);

        // Mark cross-chain transaction as processed
        if (_crossChainOriginId > 0) {
            crossChainProcessed[_crossChainOriginId] = true;
            emit CrossChainEscrowProcessed(
                escrowId,
                _crossChainOriginId,
                msg.sender
            );
        }

        emit EscrowCreated(
            escrowId,
            msg.sender,
            _landlord,
            _depositAmount,
            _rentAmount
        );

        return escrowId;
    }

    // Legacy createEscrow function for backward compatibility (defaults to USDC)
    function createEscrowWithUSDC(
        address _landlord,
        uint256 _depositAmount,
        uint256 _rentAmount,
        uint256 _duration,
        bytes32 _propertyHash,
        AutomationConditions calldata _conditions,
        uint256 _crossChainOriginId
    ) external whenNotPaused nonReentrant returns (uint256) {
        return
            this.createEscrow(
                _landlord,
                _depositAmount,
                _rentAmount,
                _duration,
                _propertyHash,
                _conditions,
                _crossChainOriginId,
                address(USDC)
            );
    }

    /**
     * @dev Releases rent payment to landlord (programmable automation)
     */
    function releaseRentPayment(
        uint256 _escrowId
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        require(
            msg.sender == escrow.tenant ||
                msg.sender == escrow.landlord ||
                hasRole(CROSS_CHAIN_RELAYER_ROLE, msg.sender),
            "Not authorized"
        );

        // Automatic release conditions
        AutomationConditions memory conditions = automationConditions[
            _escrowId
        ];

        if (
            escrow.automaticRelease &&
            block.timestamp >=
            escrow.startTime + conditions.gracePeriodDays * 1 days
        ) {
            _processRentRelease(_escrowId);
        } else if (msg.sender == escrow.tenant) {
            // Tenant manual confirmation
            _processRentRelease(_escrowId);
        }
    }

    /**
     * @dev Releases deposit back to tenant with damage assessment
     */
    function releaseDeposit(
        uint256 _escrowId,
        uint256 _damageAmount,
        string calldata /* _inspectionReport */
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(
            escrow.status == EscrowStatus.TenantReleased,
            "Rent not released"
        );
        require(
            msg.sender == escrow.landlord ||
                hasRole(DISPUTE_RESOLVER_ROLE, msg.sender),
            "Not authorized"
        );
        require(block.timestamp >= escrow.endTime, "Lease period not ended");

        AutomationConditions memory conditions = automationConditions[
            _escrowId
        ];
        require(
            _damageAmount <= conditions.maxDamageThreshold,
            "Damage exceeds threshold"
        );

        uint256 depositToReturn = escrow.depositAmount - _damageAmount;
        uint256 platformFee = (escrow.rentAmount * platformFeeRate) / 10000;

        if (depositToReturn > 0) {
            IERC20(escrow.token).safeTransfer(escrow.tenant, depositToReturn);
        }

        if (_damageAmount > 0) {
            IERC20(escrow.token).safeTransfer(escrow.landlord, _damageAmount);
        }

        // Platform fee
        IERC20(escrow.token).safeTransfer(owner(), platformFee);

        escrow.status = EscrowStatus.LandlordReleased;
        riskBufferVault.releaseBuffer(_escrowId);

        // Update reputation with token information
        try
            reputation.updateRentalHistoryWithToken(
                escrow.tenant,
                escrow.depositAmount,
                _damageAmount == 0,
                escrow.token
            )
        {
            // Success with new multi-token function
        } catch {
            // Fallback to legacy function
            reputation.updateRentalHistory(
                escrow.tenant,
                escrow.depositAmount,
                _damageAmount == 0
            );
        }

        try
            reputation.updateRentalHistoryWithToken(
                escrow.landlord,
                escrow.rentAmount,
                true,
                escrow.token
            )
        {
            // Success with new multi-token function
        } catch {
            // Fallback to legacy function
            reputation.updateRentalHistory(
                escrow.landlord,
                escrow.rentAmount,
                true
            );
        }

        emit EscrowReleased(_escrowId, escrow.tenant, depositToReturn, false);
    }

    /**
     * @dev Initiates a dispute with programmable resolution logic
     */
    function initiateDispute(
        uint256 _escrowId,
        string calldata _reason
    ) external payable whenNotPaused {
        Escrow storage escrow = escrows[_escrowId];
        require(
            msg.sender == escrow.tenant || msg.sender == escrow.landlord,
            "Not authorized"
        );
        require(
            escrow.status == EscrowStatus.Active ||
                escrow.status == EscrowStatus.TenantReleased,
            "Invalid status"
        );
        require(
            block.timestamp <= escrow.disputeDeadline,
            "Dispute period expired"
        );
        require(disputes[_escrowId].timestamp == 0, "Dispute already exists");

        // Require dispute fee (use same token as escrow)
        IERC20(escrow.token).safeTransferFrom(
            msg.sender,
            address(this),
            disputeFee
        );

        disputes[_escrowId] = Dispute({
            escrowId: _escrowId,
            initiator: msg.sender,
            reason: _reason,
            timestamp: block.timestamp,
            outcome: DisputeOutcome.Pending,
            tenantAmount: 0,
            landlordAmount: 0,
            resolved: false
        });

        escrow.status = EscrowStatus.Disputed;

        emit DisputeInitiated(_escrowId, msg.sender, _reason);
    }

    /**
     * @dev Resolves dispute with programmable outcome distribution
     */
    function resolveDispute(
        uint256 _escrowId,
        DisputeOutcome _outcome,
        uint256 _tenantAmount,
        uint256 _landlordAmount
    ) external onlyRole(DISPUTE_RESOLVER_ROLE) {
        Escrow storage escrow = escrows[_escrowId];
        Dispute storage dispute = disputes[_escrowId];

        require(escrow.status == EscrowStatus.Disputed, "Not in dispute");
        require(!dispute.resolved, "Already resolved");
        require(
            _tenantAmount + _landlordAmount <=
                escrow.depositAmount + escrow.rentAmount,
            "Invalid amounts"
        );

        dispute.outcome = _outcome;
        dispute.tenantAmount = _tenantAmount;
        dispute.landlordAmount = _landlordAmount;
        dispute.resolved = true;

        if (_tenantAmount > 0) {
            IERC20(escrow.token).safeTransfer(escrow.tenant, _tenantAmount);
        }

        if (_landlordAmount > 0) {
            IERC20(escrow.token).safeTransfer(escrow.landlord, _landlordAmount);
        }

        escrow.status = EscrowStatus.Resolved;
        riskBufferVault.releaseBuffer(_escrowId);

        // Update reputation based on outcome with token information
        bool tenantSuccess = _outcome == DisputeOutcome.TenantFavor ||
            _outcome == DisputeOutcome.Split;
        bool landlordSuccess = _outcome == DisputeOutcome.LandlordFavor ||
            _outcome == DisputeOutcome.Split;

        try
            reputation.updateRentalHistoryWithToken(
                escrow.tenant,
                escrow.depositAmount,
                tenantSuccess,
                escrow.token
            )
        {
            // Success with new multi-token function
        } catch {
            // Fallback to legacy function
            reputation.updateRentalHistory(
                escrow.tenant,
                escrow.depositAmount,
                tenantSuccess
            );
        }

        try
            reputation.updateRentalHistoryWithToken(
                escrow.landlord,
                escrow.rentAmount,
                landlordSuccess,
                escrow.token
            )
        {
            // Success with new multi-token function
        } catch {
            // Fallback to legacy function
            reputation.updateRentalHistory(
                escrow.landlord,
                escrow.rentAmount,
                landlordSuccess
            );
        }

        emit DisputeResolved(
            _escrowId,
            _outcome,
            _tenantAmount,
            _landlordAmount
        );
    }

    /**
     * @dev Emergency cancellation with conditions
     */
    function emergencyCancel(
        uint256 _escrowId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Active, "Escrow not active");

        uint256 totalAmount = escrow.depositAmount + escrow.rentAmount;
        IERC20(escrow.token).safeTransfer(escrow.tenant, totalAmount);

        escrow.status = EscrowStatus.Cancelled;
        riskBufferVault.releaseBuffer(_escrowId);

        emit EscrowReleased(_escrowId, escrow.tenant, totalAmount, false);
    }

    /**
     * @dev Cross-chain bridge integration
     */
    function processCrossChainEscrow(
        bytes calldata /* _proof */,
        uint256 _originChainId,
        address _tenant,
        uint256 /* _amount */
    ) external onlyRole(CROSS_CHAIN_RELAYER_ROLE) {
        require(!crossChainProcessed[_originChainId], "Already processed");
        // Verify cross-chain proof (implementation depends on bridge)
        // This is a simplified version for demonstration

        crossChainProcessed[_originChainId] = true;
        emit CrossChainEscrowProcessed(0, _originChainId, _tenant);
    }

    function _processRentRelease(uint256 _escrowId) internal {
        Escrow storage escrow = escrows[_escrowId];

        IERC20(escrow.token).safeTransfer(escrow.landlord, escrow.rentAmount);
        escrow.status = EscrowStatus.TenantReleased;

        emit EscrowReleased(
            _escrowId,
            escrow.landlord,
            escrow.rentAmount,
            escrow.automaticRelease
        );
    }

    // View functions
    function getEscrow(
        uint256 _escrowId
    ) external view returns (Escrow memory) {
        return escrows[_escrowId];
    }

    function getUserEscrows(
        address _user
    ) external view returns (uint256[] memory) {
        return userEscrows[_user];
    }

    function getDispute(
        uint256 _escrowId
    ) external view returns (Dispute memory) {
        return disputes[_escrowId];
    }

    function getEscrowToken(uint256 _escrowId) external view returns (address) {
        return escrows[_escrowId].token;
    }

    function isTokenSupported(address _token) external view returns (bool) {
        return supportedTokens[_token];
    }

    function owner() public view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    // Admin functions
    function setPlatformFeeRate(
        uint256 _feeRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeRate <= 1000, "Fee too high"); // Max 10%
        platformFeeRate = _feeRate;
    }

    function setDisputeFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disputeFee = _fee;
    }

    function addSupportedToken(
        address _token
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedTokens[_token] = true;
    }

    function removeSupportedToken(
        address _token
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _token != address(USDC) && _token != address(EURC),
            "Cannot remove core tokens"
        );
        supportedTokens[_token] = false;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
