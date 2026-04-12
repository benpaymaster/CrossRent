// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

// ... Your original imports ...
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// NEW: Uniswap v4 Imports for the Hookathon
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// ... Keep your IReputationSBT and IRiskBufferVault interfaces exactly as they were ...

contract RentCreditEscrow is
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    IUnlockCallback // Add this interface for v4
{
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    // --- NEW: Uniswap v4 State ---
    IPoolManager public immutable poolManager;
    address public hookAddress;
    
    // --- Your original roles and state ---
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");
    bytes32 public constant CROSS_CHAIN_RELAYER_ROLE = keccak256("CROSS_CHAIN_RELAYER_ROLE");

    IERC20 public immutable USDC;
    IERC20 public immutable EURC;
    IReputationSBT public reputation;
    IRiskBufferVault public riskBufferVault;

    // ... Keep your Enums (EscrowStatus, DisputeOutcome) and Structs (Escrow, Dispute, AutomationConditions) ...

    // ... Keep all your mappings and variables (nextEscrowId, platformFeeRate, etc.) ...

    constructor(
        address _usdc,
        address _eurc,
        address _reputation,
        address _riskBufferVault,
        address _poolManager, // NEW
        address _hookAddress  // NEW
    ) {
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        reputation = IReputationSBT(_reputation);
        riskBufferVault = IRiskBufferVault(_riskBufferVault);
        
        // NEW: Hookathon setup
        poolManager = IPoolManager(_poolManager);
        hookAddress = _hookAddress;

        supportedTokens[_usdc] = true;
        supportedTokens[_eurc] = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_RESOLVER_ROLE, msg.sender);
    }

    /**
     * @dev UPDATED: Creates escrow and deploys to Uniswap v4 Hook for yield
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
        // --- Your original validation checks ---
        require(_landlord != address(0) && _landlord != msg.sender, "Invalid landlord");
        require(_depositAmount > 0 && _rentAmount > 0, "Invalid amounts");
        require(_duration > 0 && _duration <= MAX_ESCROW_DURATION, "Invalid duration");
        require(supportedTokens[_token], "Unsupported token");

        uint256 totalAmount = _depositAmount + _rentAmount;
        uint256 escrowId = nextEscrowId++;

        // 1. Transfer token from tenant
        IERC20(_token).safeTransferFrom(msg.sender, address(this), totalAmount);

        // 2. NEW: The Hookathon "Magic" 
        // We tell Uniswap: "We want to use this money to earn yield"
        bytes memory hookData = abi.encode(msg.sender, _landlord, block.timestamp + _duration);
        
        // This triggers the v4 Flash Accounting loop
        poolManager.unlock(
            abi.encode(
                _token, 
                totalAmount, 
                hookData
            )
        );

        // 3. Your original risk buffer and storage logic (Keep this!)
        uint256 bufferAmount = (totalAmount * 1000) / 10000;
        // ... (Keep your try/catch for the riskBufferVault here) ...

        escrows[escrowId] = Escrow({
            id: escrowId,
            tenant: msg.sender,
            landlord: _landlord,
            depositAmount: _depositAmount,
            rentAmount: _rentAmount,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            status: EscrowStatus.Active,
            automaticRelease: !_conditions.requiresTenantConfirmation && !_conditions.requiresPhysicalInspection,
            disputeDeadline: block.timestamp + _duration + MIN_DISPUTE_PERIOD,
            crossChainOriginId: _crossChainOriginId,
            propertyHash: _propertyHash,
            token: _token
        });

        automationConditions[escrowId] = _conditions;
        userEscrows[msg.sender].push(escrowId);
        userEscrows[_landlord].push(escrowId);

        emit EscrowCreated(escrowId, msg.sender, _landlord, _depositAmount, _rentAmount);
        return escrowId;
    }

    /**
 * @dev Day 3: The Flash Accounting "Engine Room"
 * This settles the debt to the PoolManager using the tenant's funds.
 */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
    require(msg.sender == address(poolManager), "Only PoolManager");

    // 1. Decode the data we sent in createEscrow
    (address token, uint256 amount, bytes memory hookData) = abi.decode(data, (address, uint256, bytes));

    // 2. Wrap the token into a v4 Currency type
    Currency currency = CurrencyLibrary.fromAddress(token);

    // 3. Settle the debt: This tells the PoolManager "I am giving you these tokens"
    // We send the tokens from this Escrow contract to the PoolManager
    IERC20(token).safeTransfer(address(poolManager), amount);
    
    // 4. Record that we paid the PoolManager
    poolManager.settle(currency);

    // 5. Day 4 Preview: Here is where we will eventually call modifyLiquidity 
    // to actually mint the LP position. For Day 3, we focus on the settlement flow.

    return "";
    }