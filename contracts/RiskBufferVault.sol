// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RiskBufferVault
 * @dev ERC4626 vault for managing risk buffers for rental escrows using USDC
 * Provides yield generation and automated risk management for the RentCredit system
 */
contract RiskBufferVault is ERC4626, AccessControlEnumerable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    struct BufferLock {
        uint256 amount;
        uint256 escrowId;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        bool released;
        address escrowAddress;
    }

    struct RiskMetrics {
        uint256 totalLocked;
        uint256 totalReleased;
        uint256 totalClaimed; // For disputes/damages
        uint256 utilizationRate; // percentage * 100
        uint256 avgLockDuration;
        uint256 yieldGenerated;
    }

    struct YieldStrategy {
        bool enabled;
        uint256 targetApy; // basis points (e.g., 500 = 5%)
        uint256 maxUtilization; // max % of assets that can be deployed
        uint256 rebalanceThreshold;
        address strategy; // External yield strategy contract
    }

    mapping(uint256 => BufferLock) public bufferLocks;
    mapping(address => uint256[]) public userLocks;
    mapping(uint256 => bool) public emergencyUnlocked;

    RiskMetrics public riskMetrics;
    YieldStrategy public yieldStrategy;

    uint256 public nextLockId = 1;
    uint256 public constant MINIMUM_BUFFER_AMOUNT = 10e6; // $10 USDC minimum
    uint256 public constant MAXIMUM_LOCK_DURATION = 365 days;
    uint256 public constant EMERGENCY_WITHDRAW_PENALTY = 500; // 5% penalty
    uint256 public protocolFeeRate = 100; // 1% of yield

    // Risk management parameters
    uint256 public maxIndividualLock = 100000e6; // $100k max per escrow
    uint256 public totalRiskLimit = 10000000e6; // $10M total limit
    uint256 public liquidityReserveRatio = 2000; // 20% liquidity reserve

    event BufferLocked(
        uint256 indexed lockId,
        uint256 indexed escrowId,
        address indexed user,
        uint256 amount,
        uint256 unlockTime
    );

    event BufferReleased(
        uint256 indexed lockId,
        uint256 indexed escrowId,
        uint256 amount,
        bool emergency
    );

    event BufferClaimed(
        uint256 indexed lockId,
        uint256 indexed escrowId,
        uint256 claimedAmount,
        address claimant
    );

    event YieldDistributed(
        uint256 totalYield,
        uint256 protocolFee,
        uint256 userYield
    );

    event RiskMetricsUpdated(
        uint256 totalLocked,
        uint256 utilizationRate,
        uint256 yieldGenerated
    );

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_MANAGER_ROLE, msg.sender);

        // Initialize yield strategy
        yieldStrategy = YieldStrategy({
            enabled: false,
            targetApy: 500, // 5% APY
            maxUtilization: 8000, // 80% max utilization
            rebalanceThreshold: 1000, // 10% threshold for rebalancing
            strategy: address(0)
        });
    }

    /**
     * @dev Locks buffer for a specific escrow
     */
    function lockBuffer(uint256 escrowId, uint256 amount) 
        external 
        onlyRole(ESCROW_MANAGER_ROLE) 
        whenNotPaused 
        nonReentrant 
    {
        require(amount >= MINIMUM_BUFFER_AMOUNT, "Amount too small");
        require(amount <= maxIndividualLock, "Amount exceeds individual limit");
        require(riskMetrics.totalLocked + amount <= totalRiskLimit, "Exceeds total risk limit");

        uint256 lockId = nextLockId++;
        uint256 unlockTime = block.timestamp + MAXIMUM_LOCK_DURATION;

        bufferLocks[lockId] = BufferLock({
            amount: amount,
            escrowId: escrowId,
            lockTimestamp: block.timestamp,
            unlockTimestamp: unlockTime,
            released: false,
            escrowAddress: msg.sender
        });

        userLocks[msg.sender].push(lockId);

        // Update risk metrics
        riskMetrics.totalLocked += amount;
        _updateUtilizationRate();

        // Transfer USDC from escrow to vault and mint shares
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit BufferLocked(lockId, escrowId, msg.sender, amount, unlockTime);

        // Trigger yield strategy rebalancing if needed
        _rebalanceIfNeeded();
    }

    /**
     * @dev Releases buffer after escrow completion
     */
    function releaseBuffer(uint256 escrowId) 
        external 
        onlyRole(ESCROW_MANAGER_ROLE) 
        nonReentrant 
    {
        uint256 lockId = _findLockByEscrowId(escrowId, msg.sender);
        BufferLock storage lock = bufferLocks[lockId];
        
        require(!lock.released, "Buffer already released");
        require(lock.escrowAddress == msg.sender, "Not authorized");

        lock.released = true;

        // Update risk metrics
        riskMetrics.totalReleased += lock.amount;
        riskMetrics.totalLocked -= lock.amount;
        _updateUtilizationRate();

        // Calculate yield to distribute
        uint256 yieldEarned = _calculateYieldEarned(lockId);
        if (yieldEarned > 0) {
            _distributeYield(yieldEarned);
        }

        // Transfer back to escrow contract
        IERC20(asset()).safeTransfer(msg.sender, lock.amount);

        emit BufferReleased(lockId, escrowId, lock.amount, false);
    }

    /**
     * @dev Claims buffer for dispute resolution or damages
     */
    function claimBuffer(
        uint256 escrowId, 
        uint256 claimAmount,
        address claimant
    ) 
        external 
        onlyRole(ESCROW_MANAGER_ROLE) 
        nonReentrant 
    {
        uint256 lockId = _findLockByEscrowId(escrowId, msg.sender);
        BufferLock storage lock = bufferLocks[lockId];
        
        require(!lock.released, "Buffer already released");
        require(claimAmount <= lock.amount, "Claim exceeds buffer");
        require(lock.escrowAddress == msg.sender, "Not authorized");

        // Update lock amount
        lock.amount -= claimAmount;
        if (lock.amount == 0) {
            lock.released = true;
        }

        // Update risk metrics
        riskMetrics.totalClaimed += claimAmount;
        riskMetrics.totalLocked -= claimAmount;
        _updateUtilizationRate();

        // Transfer claimed amount to claimant
        IERC20(asset()).safeTransfer(claimant, claimAmount);

        emit BufferClaimed(lockId, escrowId, claimAmount, claimant);
    }

    /**
     * @dev Emergency buffer release (with penalty)
     */
    function emergencyReleaseBuffer(uint256 lockId) 
        external 
        onlyRole(RISK_MANAGER_ROLE) 
        nonReentrant 
    {
        BufferLock storage lock = bufferLocks[lockId];
        require(!lock.released, "Buffer already released");

        uint256 penalty = (lock.amount * EMERGENCY_WITHDRAW_PENALTY) / 10000;
        uint256 releaseAmount = lock.amount - penalty;

        lock.released = true;
        emergencyUnlocked[lockId] = true;

        // Update risk metrics
        riskMetrics.totalReleased += lock.amount;
        riskMetrics.totalLocked -= lock.amount;
        _updateUtilizationRate();

        // Transfer release amount back to escrow, keep penalty
        IERC20(asset()).safeTransfer(lock.escrowAddress, releaseAmount);

        emit BufferReleased(lockId, lock.escrowId, releaseAmount, true);
    }

    /**
     * @dev Deposits USDC into the vault for yield generation
     */
    function deposit(uint256 assets, address receiver) 
        public 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        require(assets > 0, "Cannot deposit 0");
        
        uint256 shares = super.deposit(assets, receiver);
        
        // Trigger yield strategy rebalancing
        _rebalanceIfNeeded();
        
        return shares;
    }

    /**
     * @dev Withdraws assets from the vault
     */
    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        require(assets <= _availableLiquidity(), "Insufficient liquidity");
        
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev Calculates maximum withdrawable amount considering locked buffers
     */
    function maxWithdraw(address owner) 
        public 
        view 
        override 
        returns (uint256) 
    {
        uint256 maxAssets = super.maxWithdraw(owner);
        uint256 availableLiquidity = _availableLiquidity();
        
        return maxAssets > availableLiquidity ? availableLiquidity : maxAssets;
    }

    /**
     * @dev Calculates available liquidity (total assets - locked buffers - reserve)
     */
    function _availableLiquidity() internal view returns (uint256) {
        uint256 totalAssets = IERC20(asset()).balanceOf(address(this));
        uint256 requiredReserve = (riskMetrics.totalLocked * liquidityReserveRatio) / 10000;
        uint256 lockedAssets = riskMetrics.totalLocked + requiredReserve;
        
        return totalAssets > lockedAssets ? totalAssets - lockedAssets : 0;
    }

    /**
     * @dev Finds lock by escrow ID and escrow address
     */
    function _findLockByEscrowId(uint256 escrowId, address escrowAddress) 
        internal 
        view 
        returns (uint256) 
    {
        uint256[] memory locks = userLocks[escrowAddress];
        for (uint256 i = 0; i < locks.length; i++) {
            BufferLock memory lock = bufferLocks[locks[i]];
            if (lock.escrowId == escrowId && !lock.released) {
                return locks[i];
            }
        }
        revert("Lock not found");
    }

    /**
     * @dev Updates utilization rate metric
     */
    function _updateUtilizationRate() internal {
        uint256 totalAssets = IERC20(asset()).balanceOf(address(this));
        if (totalAssets > 0) {
            riskMetrics.utilizationRate = (riskMetrics.totalLocked * 10000) / totalAssets;
        }

        emit RiskMetricsUpdated(
            riskMetrics.totalLocked,
            riskMetrics.utilizationRate,
            riskMetrics.yieldGenerated
        );
    }

    /**
     * @dev Calculates yield earned for a specific lock
     */
    function _calculateYieldEarned(uint256 lockId) internal view returns (uint256) {
        BufferLock memory lock = bufferLocks[lockId];
        if (!yieldStrategy.enabled) return 0;

        uint256 duration = block.timestamp - lock.lockTimestamp;
        uint256 annualizedYield = (lock.amount * yieldStrategy.targetApy) / 10000;
        uint256 yieldEarned = (annualizedYield * duration) / 365 days;

        return yieldEarned;
    }

    /**
     * @dev Distributes yield between users and protocol
     */
    function _distributeYield(uint256 totalYield) internal {
        uint256 protocolFee = (totalYield * protocolFeeRate) / 10000;
        uint256 userYield = totalYield - protocolFee;

        riskMetrics.yieldGenerated += totalYield;

        // Transfer protocol fee to admin
        if (protocolFee > 0) {
            address admin = address(0); // Get admin from role members
            uint256 adminCount = getRoleMemberCount(DEFAULT_ADMIN_ROLE);
            if (adminCount > 0) {
                admin = getRoleMember(DEFAULT_ADMIN_ROLE, 0);
            }
            if (admin != address(0)) {
                IERC20(asset()).safeTransfer(admin, protocolFee);
            }
        }

        emit YieldDistributed(totalYield, protocolFee, userYield);
    }

    /**
     * @dev Rebalances yield strategy if threshold is reached
     */
    function _rebalanceIfNeeded() internal {
        if (!yieldStrategy.enabled || yieldStrategy.strategy == address(0)) return;

        uint256 currentUtilization = riskMetrics.utilizationRate;
        uint256 targetUtilization = yieldStrategy.maxUtilization;
        
        if (currentUtilization > targetUtilization + yieldStrategy.rebalanceThreshold ||
            currentUtilization < targetUtilization - yieldStrategy.rebalanceThreshold) {
            // Trigger rebalancing logic (simplified for demo)
            // In production, this would call external yield strategy
        }
    }

    // View functions
    function getBufferLock(uint256 lockId) external view returns (BufferLock memory) {
        return bufferLocks[lockId];
    }

    function getUserLocks(address user) external view returns (uint256[] memory) {
        return userLocks[user];
    }

    function getRiskMetrics() external view returns (RiskMetrics memory) {
        return riskMetrics;
    }

    function getYieldStrategy() external view returns (YieldStrategy memory) {
        return yieldStrategy;
    }

    function getTotalValueLocked() external view returns (uint256) {
        return riskMetrics.totalLocked;
    }

    function getAvailableLiquidity() external view returns (uint256) {
        return _availableLiquidity();
    }

    // Admin functions
    function setYieldStrategy(
        bool enabled,
        uint256 targetApy,
        uint256 maxUtilization,
        uint256 rebalanceThreshold,
        address strategy
    ) external onlyRole(RISK_MANAGER_ROLE) {
        yieldStrategy = YieldStrategy({
            enabled: enabled,
            targetApy: targetApy,
            maxUtilization: maxUtilization,
            rebalanceThreshold: rebalanceThreshold,
            strategy: strategy
        });
    }

    function setRiskParameters(
        uint256 _maxIndividualLock,
        uint256 _totalRiskLimit,
        uint256 _liquidityReserveRatio
    ) external onlyRole(RISK_MANAGER_ROLE) {
        require(_liquidityReserveRatio <= 5000, "Reserve ratio too high"); // Max 50%
        
        maxIndividualLock = _maxIndividualLock;
        totalRiskLimit = _totalRiskLimit;
        liquidityReserveRatio = _liquidityReserveRatio;
    }

    function setProtocolFeeRate(uint256 _feeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeRate <= 2000, "Fee rate too high"); // Max 20%
        protocolFeeRate = _feeRate;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function grantEscrowManager(address escrowContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(ESCROW_MANAGER_ROLE, escrowContract);
    }

    function revokeEscrowManager(address escrowContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ESCROW_MANAGER_ROLE, escrowContract);
    }

    // Emergency functions
    function emergencyWithdraw(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(amount <= _availableLiquidity(), "Insufficient liquidity");
        IERC20(asset()).safeTransfer(msg.sender, amount);
    }

    // Override to ensure solvency
    function _update(address from, address to, uint256 value) 
        internal 
        override 
        whenNotPaused 
    {
        super._update(from, to, value);
    }
}
