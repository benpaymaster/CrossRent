// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RiskBufferVault (Hardened)
 * @dev ERC4626 vault managing escrow risk buffers with secure locking + claims
 */
contract RiskBufferVault is ERC4626, AccessControlEnumerable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================
    // ROLES
    // =========================
    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    // =========================
    // DATA STRUCTURES
    // =========================
    struct BufferLock {
        uint256 amount;
        uint256 escrowId;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        bool released;
        address escrowContract;
        address beneficiary;
    }

    struct RiskMetrics {
        uint256 totalLocked;
        uint256 totalReleased;
        uint256 totalClaimed;
        uint256 utilizationRate;
        uint256 yieldGenerated;
    }

    struct YieldStrategy {
        bool enabled;
        uint256 targetApy;
        uint256 maxUtilization;
        uint256 rebalanceThreshold;
        address strategy;
    }

    // =========================
    // STORAGE
    // =========================
    mapping(uint256 => BufferLock) public bufferLocks;
    mapping(uint256 => bool) public lockExists;

    mapping(address => uint256[]) private userLocks;

    RiskMetrics public riskMetrics;
    YieldStrategy public yieldStrategy;

    uint256 public nextLockId = 1;

    uint256 public constant MINIMUM_BUFFER = 10e6;
    uint256 public constant MAX_LOCK_DURATION = 365 days;

    uint256 public maxIndividualLock = 100000e6;
    uint256 public totalRiskLimit = 10_000_000e6;

    uint256 public liquidityReserveRatio = 2000; // 20%

    uint256 public protocolFeeRate = 100; // 1%

    // =========================
    // EVENTS
    // =========================
    event BufferLocked(uint256 indexed lockId, uint256 indexed escrowId, address indexed escrow, uint256 amount);
    event BufferReleased(uint256 indexed lockId, uint256 indexed escrowId, uint256 amount);
    event BufferClaimed(uint256 indexed lockId, uint256 indexed escrowId, uint256 amount);
    event YieldDistributed(uint256 totalYield, uint256 fee, uint256 userShare);

    // =========================
    // ERRORS
    // =========================
    error InvalidAmount();
    error LockNotFound();
    error AlreadyReleased();
    error Unauthorized();
    error ExceedsRiskLimit();

    // =========================
    // CONSTRUCTOR
    // =========================
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_MANAGER_ROLE, msg.sender);
    }

    // =========================
    // LOCK BUFFER (HARDENED)
    // =========================
    function lockBuffer(
        uint256 escrowId,
        uint256 amount,
        address beneficiary
    )
        external
        onlyRole(ESCROW_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 lockId)
    {
        if (amount < MINIMUM_BUFFER) revert InvalidAmount();
        if (amount > maxIndividualLock) revert InvalidAmount();
        if (riskMetrics.totalLocked + amount > totalRiskLimit) revert ExceedsRiskLimit();
        if (beneficiary == address(0)) revert Unauthorized();

        lockId = nextLockId++;

        bufferLocks[lockId] = BufferLock({
            amount: amount,
            escrowId: escrowId,
            lockTimestamp: block.timestamp,
            unlockTimestamp: block.timestamp + MAX_LOCK_DURATION,
            released: false,
            escrowContract: msg.sender,
            beneficiary: beneficiary
        });

        lockExists[lockId] = true;
        userLocks[beneficiary].push(lockId);

        riskMetrics.totalLocked += amount;
        _updateUtilization();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit BufferLocked(lockId, escrowId, msg.sender, amount);
    }

    // =========================
    // RELEASE BUFFER (SAFE)
    // =========================
    function releaseBuffer(uint256 lockId)
        external
        onlyRole(ESCROW_MANAGER_ROLE)
        nonReentrant
    {
        if (!lockExists[lockId]) revert LockNotFound();

        BufferLock storage lock = bufferLocks[lockId];

        if (lock.released) revert AlreadyReleased();

        lock.released = true;

        riskMetrics.totalReleased += lock.amount;
        riskMetrics.totalLocked -= lock.amount;

        _updateUtilization();

        IERC20(asset()).safeTransfer(lock.escrowContract, lock.amount);

        emit BufferReleased(lockId, lock.escrowId, lock.amount);
    }

    // =========================
    // CLAIM BUFFER (DISPUTES)
    // =========================
    function claimBuffer(
        uint256 lockId,
        uint256 amount,
        address recipient
    )
        external
        onlyRole(ESCROW_MANAGER_ROLE)
        nonReentrant
    {
        if (!lockExists[lockId]) revert LockNotFound();

        BufferLock storage lock = bufferLocks[lockId];

        if (lock.released) revert AlreadyReleased();
        if (amount == 0 || amount > lock.amount) revert InvalidAmount();

        lock.amount -= amount;

        if (lock.amount == 0) {
            lock.released = true;
        }

        riskMetrics.totalClaimed += amount;
        riskMetrics.totalLocked -= amount;

        _updateUtilization();

        IERC20(asset()).safeTransfer(recipient, amount);

        emit BufferClaimed(lockId, lock.escrowId, amount);
    }

    // =========================
    // EMERGENCY RELEASE
    // =========================
    function emergencyRelease(uint256 lockId)
        external
        onlyRole(RISK_MANAGER_ROLE)
        nonReentrant
    {
        if (!lockExists[lockId]) revert LockNotFound();

        BufferLock storage lock = bufferLocks[lockId];

        if (lock.released) revert AlreadyReleased();

        uint256 penalty = (lock.amount * 500) / 10000; // 5%
        uint256 payout = lock.amount - penalty;

        lock.released = true;

        riskMetrics.totalReleased += lock.amount;
        riskMetrics.totalLocked -= lock.amount;

        _updateUtilization();

        IERC20(asset()).safeTransfer(lock.beneficiary, payout);

        emit BufferReleased(lockId, lock.escrowId, payout);
    }

    // =========================
    // ERC4626 SAFETY OVERRIDES
    // =========================
    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(assets > 0, "ZERO_ASSETS");
        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(assets <= _availableLiquidity(), "INSUFFICIENT_LIQUIDITY");
        return super.withdraw(assets, receiver, owner);
    }

    function maxWithdraw(address owner)
        public
        view
        override
        returns (uint256)
    {
        uint256 liquidity = _availableLiquidity();
        uint256 base = super.maxWithdraw(owner);
        return base > liquidity ? liquidity : base;
    }

    // =========================
    // LIQUIDITY CALC
    // =========================
    function _availableLiquidity() internal view returns (uint256) {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 reserve = (riskMetrics.totalLocked * liquidityReserveRatio) / 10000;

        if (bal <= reserve) return 0;
        return bal - reserve;
    }

    // =========================
    // METRICS
    // =========================
    function _updateUtilization() internal {
        uint256 bal = IERC20(asset()).balanceOf(address(this));

        if (bal > 0) {
            riskMetrics.utilizationRate =
                (riskMetrics.totalLocked * 10000) / bal;
        }
    }

    // =========================
    // ADMIN CONFIG
    // =========================
    function setRiskParameters(
        uint256 maxLock,
        uint256 totalLimit,
        uint256 reserveRatio
    ) external onlyRole(RISK_MANAGER_ROLE) {
        require(reserveRatio <= 5000, "TOO_HIGH");
        maxIndividualLock = maxLock;
        totalRiskLimit = totalLimit;
        liquidityReserveRatio = reserveRatio;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // =========================
    // SAFETY HOOK
    // =========================
    function _update(address from, address to, uint256 value)
        internal
        override
    {
        super._update(from, to, value);
    }
}