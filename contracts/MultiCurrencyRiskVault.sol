// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiCurrencyRiskVault
 * @dev Multi-currency risk buffer vault supporting both USDC and EURC
 * Provides yield generation and automated risk management for cross-border rental escrows
 * 
 * This addresses Challenge 1: Multi-Currency Support by maintaining separate
 * pools for USDC and EURC while providing unified risk management
 */
contract MultiCurrencyRiskVault is AccessControlEnumerable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    // Supported currencies
    IERC20 public immutable USDC;
    IERC20 public immutable EURC;

    struct CurrencyPool {
        uint256 totalDeposits;    // Total deposits in this currency
        uint256 totalLocked;      // Amount locked in escrows
        uint256 totalYield;       // Accumulated yield
        uint256 utilizationRate;  // Utilization percentage (basis points)
        uint256 targetApy;        // Target APY (basis points)
        bool enabled;             // Whether deposits are enabled
    }

    struct BufferLock {
        uint256 amount;
        uint256 escrowId;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        bool released;
        address escrowAddress;
        IERC20 currency;          // Which currency is locked
    }

    struct UserPosition {
        uint256 usdcDeposits;
        uint256 eurcDeposits;
        uint256 usdcYield;
        uint256 eurcYield;
        uint256[] activeLocks;
    }

    // Currency pools
    mapping(IERC20 => CurrencyPool) public currencyPools;
    
    // Buffer locks by ID
    mapping(uint256 => BufferLock) public bufferLocks;
    
    // User positions
    mapping(address => UserPosition) public userPositions;
    
    // User locks array
    mapping(address => uint256[]) public userLocks;

    // Global state
    uint256 public nextLockId = 1;
    uint256 public constant MIN_DEPOSIT = 10e6; // $10 minimum (6 decimals)
    uint256 public constant MAX_UTILIZATION = 8000; // 80% max utilization
    uint256 public constant YIELD_DISTRIBUTION_INTERVAL = 24 hours;

    // Events
    event Deposit(address indexed user, IERC20 indexed currency, uint256 amount);
    event Withdraw(address indexed user, IERC20 indexed currency, uint256 amount);
    event BufferLocked(uint256 indexed lockId, uint256 indexed escrowId, IERC20 indexed currency, uint256 amount);
    event BufferReleased(uint256 indexed lockId, uint256 amount);
    event YieldDistributed(IERC20 indexed currency, uint256 totalYield);
    event CurrencyPoolUpdated(IERC20 indexed currency, bool enabled, uint256 targetApy);

    constructor(address _usdc, address _eurc) {
        require(_usdc != address(0) && _eurc != address(0), "Invalid currency addresses");
        
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        
        // Initialize currency pools
        currencyPools[USDC] = CurrencyPool({
            totalDeposits: 0,
            totalLocked: 0,
            totalYield: 0,
            utilizationRate: 0,
            targetApy: 500, // 5% APY
            enabled: true
        });
        
        currencyPools[EURC] = CurrencyPool({
            totalDeposits: 0,
            totalLocked: 0,
            totalYield: 0,
            utilizationRate: 0,
            targetApy: 450, // 4.5% APY
            enabled: true
        });

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Deposit USDC or EURC into the vault
     * @param currency The currency to deposit (USDC or EURC)
     * @param amount Amount to deposit
     */
    function deposit(IERC20 currency, uint256 amount) external whenNotPaused nonReentrant {
        require(amount >= MIN_DEPOSIT, "Deposit below minimum");
        require(isSupportedCurrency(currency), "Unsupported currency");
        require(currencyPools[currency].enabled, "Currency deposits disabled");

        // Transfer tokens to vault
        currency.safeTransferFrom(msg.sender, address(this), amount);

        // Update pool state
        currencyPools[currency].totalDeposits += amount;
        
        // Update user position
        if (currency == USDC) {
            userPositions[msg.sender].usdcDeposits += amount;
        } else {
            userPositions[msg.sender].eurcDeposits += amount;
        }

        emit Deposit(msg.sender, currency, amount);
    }

    /**
     * @dev Withdraw deposited funds (minus any locked amounts)
     * @param currency The currency to withdraw
     * @param amount Amount to withdraw
     */
    function withdraw(IERC20 currency, uint256 amount) external whenNotPaused nonReentrant {
        require(isSupportedCurrency(currency), "Unsupported currency");
        
        UserPosition storage position = userPositions[msg.sender];
        uint256 userDeposits = currency == USDC ? position.usdcDeposits : position.eurcDeposits;
        
        require(amount <= userDeposits, "Insufficient balance");
        require(amount <= getAvailableBalance(currency), "Insufficient liquidity");

        // Update state
        currencyPools[currency].totalDeposits -= amount;
        
        if (currency == USDC) {
            position.usdcDeposits -= amount;
        } else {
            position.eurcDeposits -= amount;
        }

        // Transfer tokens
        currency.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, currency, amount);
    }

    /**
     * @dev Lock buffer for an escrow (called by escrow contracts)
     * @param escrowId The escrow ID
     * @param currency The currency to lock
     * @param amount Amount to lock
     * @param duration Lock duration in seconds
     * @param escrowAddress Address of the escrow contract
     */
    function lockBuffer(
        uint256 escrowId,
        IERC20 currency,
        uint256 amount,
        uint256 duration,
        address escrowAddress
    ) external onlyRole(ESCROW_MANAGER_ROLE) whenNotPaused nonReentrant returns (uint256 lockId) {
        require(isSupportedCurrency(currency), "Unsupported currency");
        require(amount > 0, "Invalid amount");
        require(duration > 0, "Invalid duration");
        require(escrowAddress != address(0), "Invalid escrow address");

        // Check available liquidity
        require(getAvailableBalance(currency) >= amount, "Insufficient liquidity");

        // Create lock
        lockId = nextLockId++;
        bufferLocks[lockId] = BufferLock({
            amount: amount,
            escrowId: escrowId,
            lockTimestamp: block.timestamp,
            unlockTimestamp: block.timestamp + duration,
            released: false,
            escrowAddress: escrowAddress,
            currency: currency
        });

        // Update pool state
        currencyPools[currency].totalLocked += amount;
        _updateUtilizationRate(currency);

        emit BufferLocked(lockId, escrowId, currency, amount);
    }

    /**
     * @dev Release locked buffer back to the pool
     * @param lockId The lock ID to release
     */
    function releaseBuffer(uint256 lockId) external onlyRole(ESCROW_MANAGER_ROLE) whenNotPaused nonReentrant {
        BufferLock storage lock = bufferLocks[lockId];
        require(lock.amount > 0, "Lock does not exist");
        require(!lock.released, "Already released");
        require(block.timestamp >= lock.unlockTimestamp, "Lock not expired");

        // Update state
        lock.released = true;
        currencyPools[lock.currency].totalLocked -= lock.amount;
        _updateUtilizationRate(lock.currency);

        emit BufferReleased(lockId, lock.amount);
    }

    /**
     * @dev Claim locked buffer for dispute resolution
     * @param lockId The lock ID to claim
     * @param recipient Address to receive the funds
     * @param amount Amount to claim (may be partial)
     */
    function claimBuffer(
        uint256 lockId,
        address recipient,
        uint256 amount
    ) external onlyRole(RISK_MANAGER_ROLE) whenNotPaused nonReentrant {
        BufferLock storage lock = bufferLocks[lockId];
        require(lock.amount > 0, "Lock does not exist");
        require(!lock.released, "Already released");
        require(amount <= lock.amount, "Amount exceeds lock");
        require(recipient != address(0), "Invalid recipient");

        // Update lock
        lock.amount -= amount;
        if (lock.amount == 0) {
            lock.released = true;
        }

        // Update pool state
        currencyPools[lock.currency].totalLocked -= amount;
        currencyPools[lock.currency].totalDeposits -= amount; // Permanent removal
        _updateUtilizationRate(lock.currency);

        // Transfer to recipient
        lock.currency.safeTransfer(recipient, amount);

        emit BufferReleased(lockId, amount);
    }

    /**
     * @dev Get available balance for a currency (total deposits - locked amounts)
     */
    function getAvailableBalance(IERC20 currency) public view returns (uint256) {
        CurrencyPool memory pool = currencyPools[currency];
        return pool.totalDeposits - pool.totalLocked;
    }

    /**
     * @dev Check if a currency is supported
     */
    function isSupportedCurrency(IERC20 currency) public view returns (bool) {
        return currency == USDC || currency == EURC;
    }

    /**
     * @dev Get user's total deposited amount for a currency
     */
    function getUserBalance(address user, IERC20 currency) external view returns (uint256) {
        if (currency == USDC) {
            return userPositions[user].usdcDeposits;
        } else if (currency == EURC) {
            return userPositions[user].eurcDeposits;
        }
        return 0;
    }

    /**
     * @dev Get comprehensive vault statistics
     */
    function getVaultStats() external view returns (
        uint256 totalUsdcDeposits,
        uint256 totalEurcDeposits,
        uint256 totalUsdcLocked,
        uint256 totalEurcLocked,
        uint256 usdcUtilization,
        uint256 eurcUtilization
    ) {
        totalUsdcDeposits = currencyPools[USDC].totalDeposits;
        totalEurcDeposits = currencyPools[EURC].totalDeposits;
        totalUsdcLocked = currencyPools[USDC].totalLocked;
        totalEurcLocked = currencyPools[EURC].totalLocked;
        usdcUtilization = currencyPools[USDC].utilizationRate;
        eurcUtilization = currencyPools[EURC].utilizationRate;
    }

    /**
     * @dev Update currency pool configuration
     */
    function updateCurrencyPool(
        IERC20 currency,
        bool enabled,
        uint256 targetApy
    ) external onlyRole(RISK_MANAGER_ROLE) {
        require(isSupportedCurrency(currency), "Unsupported currency");
        require(targetApy <= 2000, "APY too high"); // Max 20%

        currencyPools[currency].enabled = enabled;
        currencyPools[currency].targetApy = targetApy;

        emit CurrencyPoolUpdated(currency, enabled, targetApy);
    }

    /**
     * @dev Internal function to update utilization rate
     */
    function _updateUtilizationRate(IERC20 currency) internal {
        CurrencyPool storage pool = currencyPools[currency];
        if (pool.totalDeposits > 0) {
            pool.utilizationRate = (pool.totalLocked * 10000) / pool.totalDeposits;
        } else {
            pool.utilizationRate = 0;
        }
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyRole(RISK_MANAGER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause function
     */
    function unpause() external onlyRole(RISK_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal (admin only)
     */
    function emergencyWithdraw(
        IERC20 currency,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        currency.safeTransfer(to, amount);
    }
}