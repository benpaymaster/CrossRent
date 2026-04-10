// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICircleGateway.sol";

/**
 * @title CrossRentGatewayManager
 * @notice Manages Circle Gateway programmable wallets for CrossRent escrows
 * @dev Integrates Circle Gateway for secure, developer-controlled wallet infrastructure
 */
contract CrossRentGatewayManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ESCROW_ROLE = keccak256("ESCROW_ROLE");

    ICircleGateway public immutable CIRCLE_GATEWAY;
    
    // Wallet management
    mapping(uint256 => string) public escrowToWalletId;
    mapping(string => uint256) public walletIdToEscrow;
    mapping(string => bool) public authorizedWallets;
    mapping(address => string[]) public userWallets;
    
    struct EscrowWallet {
        string walletId;
        address walletAddress;
        address landlord;
        address tenant;
        uint256 escrowId;
        bool isActive;
        uint256 createdAt;
    }
    
    mapping(string => EscrowWallet) public escrowWallets;
    string[] public allWalletIds;
    
    // Gateway configuration
    uint256 public constant ARC_BLOCKCHAIN_ID = 999; // Arc blockchain identifier
    bytes32 public entitySecretCiphertext;
    
    event WalletCreatedForEscrow(
        uint256 indexed escrowId,
        string indexed walletId,
        address indexed walletAddress,
        address landlord,
        address tenant
    );
    
    event FundsDeposited(
        string indexed walletId,
        uint256 indexed escrowId,
        address token,
        uint256 amount,
        address depositor
    );
    
    event FundsReleased(
        string indexed walletId,
        uint256 indexed escrowId,
        address token,
        uint256 amount,
        address recipient
    );
    
    event EmergencyWithdrawal(
        string indexed walletId,
        address token,
        uint256 amount,
        address recipient
    );

    error WalletNotFound();
    error WalletNotAuthorized();
    error EscrowAlreadyHasWallet();
    error InsufficientWalletBalance();
    error WalletCreationFailed();
    error TransactionFailed();

    constructor(
        address _CIRCLE_GATEWAY,
        bytes32 _entitySecretCiphertext,
        address _admin
    ) {
        CIRCLE_GATEWAY = ICircleGateway(_CIRCLE_GATEWAY);
        entitySecretCiphertext = _entitySecretCiphertext;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
    }

    /**
     * @notice Create a Circle Gateway wallet for an escrow
     * @param escrowId The rental escrow ID
     * @param landlord Landlord address
     * @param tenant Tenant address
     * @return walletId Unique wallet identifier
     */
    function createEscrowWallet(
        uint256 escrowId,
        address landlord,
        address tenant
    ) external onlyRole(ESCROW_ROLE) returns (string memory walletId) {
        if (bytes(escrowToWalletId[escrowId]).length > 0) {
            revert EscrowAlreadyHasWallet();
        }
        
        // Generate unique wallet name
        string memory walletName = string(abi.encodePacked(
            "CrossRent-Escrow-",
            _toString(escrowId),
            "-",
            _toString(block.timestamp)
        ));
        
        // Create wallet via Circle Gateway
        try CIRCLE_GATEWAY.createWallet(
            walletName,
            ARC_BLOCKCHAIN_ID,
            entitySecretCiphertext
        ) returns (string memory _walletId) {
            walletId = _walletId;
        } catch {
            revert WalletCreationFailed();
        }
        
        // Get wallet address
        address walletAddress = CIRCLE_GATEWAY.getWalletAddress(walletId);
        
        // Store wallet information
        escrowWallets[walletId] = EscrowWallet({
            walletId: walletId,
            walletAddress: walletAddress,
            landlord: landlord,
            tenant: tenant,
            escrowId: escrowId,
            isActive: true,
            createdAt: block.timestamp
        });
        
        // Update mappings
        escrowToWalletId[escrowId] = walletId;
        walletIdToEscrow[walletId] = escrowId;
        authorizedWallets[walletId] = true;
        allWalletIds.push(walletId);
        
        // Add to user wallets
        userWallets[landlord].push(walletId);
        userWallets[tenant].push(walletId);
        
        // Set wallet permissions for automated operations
        CIRCLE_GATEWAY.setWalletPermissions(walletId, address(this), type(uint256).max);
        
        emit WalletCreatedForEscrow(escrowId, walletId, walletAddress, landlord, tenant);
        
        return walletId;
    }
    
    /**
     * @notice Deposit funds to an escrow wallet
     * @dev Called after cross-chain transfer completion
     * @param walletId Target wallet identifier
     * @param token Token contract address
     * @param amount Amount to deposit
     * @param depositor Original depositor address
     */
    function depositToEscrowWallet(
        string calldata walletId,
        address token,
        uint256 amount,
        address depositor
    ) external onlyRole(ESCROW_ROLE) nonReentrant {
        if (!authorizedWallets[walletId]) revert WalletNotAuthorized();
        
        EscrowWallet storage wallet = escrowWallets[walletId];
        if (!wallet.isActive) revert WalletNotFound();
        
        // Transfer tokens to wallet
        IERC20(token).safeTransfer(wallet.walletAddress, amount);
        
        emit FundsDeposited(walletId, wallet.escrowId, token, amount, depositor);
    }
    
    /**
     * @notice Release funds from escrow wallet
     * @param walletId Source wallet identifier
     * @param token Token contract address
     * @param amount Amount to release
     * @param recipient Recipient address
     */
    function releaseFundsFromEscrow(
        string calldata walletId,
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(ESCROW_ROLE) nonReentrant {
        if (!authorizedWallets[walletId]) revert WalletNotAuthorized();
        
        EscrowWallet storage wallet = escrowWallets[walletId];
        if (!wallet.isActive) revert WalletNotFound();
        
        // Check wallet balance
        uint256 balance = CIRCLE_GATEWAY.getWalletBalance(walletId, token);
        if (balance < amount) revert InsufficientWalletBalance();
        
        // Execute transfer via Gateway
        try CIRCLE_GATEWAY.transferTokens(walletId, token, recipient, amount) {
            emit FundsReleased(walletId, wallet.escrowId, token, amount, recipient);
        } catch {
            revert TransactionFailed();
        }
    }
    
    /**
     * @notice Batch release funds to multiple recipients
     * @param walletId Source wallet identifier
     * @param token Token contract address
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to release
     */
    function batchReleaseFunds(
        string calldata walletId,
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(ESCROW_ROLE) nonReentrant {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        if (!authorizedWallets[walletId]) revert WalletNotAuthorized();
        
        EscrowWallet storage wallet = escrowWallets[walletId];
        if (!wallet.isActive) revert WalletNotFound();
        
        // Calculate total amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        // Check wallet balance
        uint256 balance = CIRCLE_GATEWAY.getWalletBalance(walletId, token);
        if (balance < totalAmount) revert InsufficientWalletBalance();
        
        // Execute transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            try CIRCLE_GATEWAY.transferTokens(walletId, token, recipients[i], amounts[i]) {
                emit FundsReleased(walletId, wallet.escrowId, token, amounts[i], recipients[i]);
            } catch {
                revert TransactionFailed();
            }
        }
    }
    
    /**
     * @notice Deactivate an escrow wallet
     * @param walletId Wallet identifier to deactivate
     */
    function deactivateEscrowWallet(string calldata walletId) 
        external 
        onlyRole(ESCROW_ROLE) 
    {
        if (!authorizedWallets[walletId]) revert WalletNotAuthorized();
        
        escrowWallets[walletId].isActive = false;
        CIRCLE_GATEWAY.setWalletPaused(walletId, true);
    }
    
    /**
     * @notice Emergency withdrawal from wallet
     * @param walletId Wallet identifier
     * @param token Token contract address
     * @param recipient Emergency recipient
     */
    function emergencyWithdraw(
        string calldata walletId,
        address token,
        address recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (!authorizedWallets[walletId]) revert WalletNotAuthorized();
        
        uint256 balance = CIRCLE_GATEWAY.getWalletBalance(walletId, token);
        
        if (balance > 0) {
            try CIRCLE_GATEWAY.transferTokens(walletId, token, recipient, balance) {
                emit EmergencyWithdrawal(walletId, token, balance, recipient);
            } catch {
                revert TransactionFailed();
            }
        }
    }
    
    /**
     * @notice Get escrow wallet details
     * @param walletId Wallet identifier
     * @return wallet Escrow wallet information
     */
    function getEscrowWallet(string calldata walletId) 
        external 
        view 
        returns (EscrowWallet memory wallet) 
    {
        return escrowWallets[walletId];
    }
    
    /**
     * @notice Get wallet balance for a token
     * @param walletId Wallet identifier
     * @param token Token contract address
     * @return balance Token balance
     */
    function getWalletBalance(string calldata walletId, address token) 
        external 
        view 
        returns (uint256 balance) 
    {
        return CIRCLE_GATEWAY.getWalletBalance(walletId, token);
    }
    
    /**
     * @notice Get all wallets for a user
     * @param user User address
     * @return walletIds Array of wallet identifiers
     */
    function getUserWallets(address user) 
        external 
        view 
        returns (string[] memory walletIds) 
    {
        return userWallets[user];
    }
    
    /**
     * @notice Get total number of wallets
     * @return count Total wallet count
     */
    function getTotalWallets() external view returns (uint256 count) {
        return allWalletIds.length;
    }
    
    /**
     * @notice Update entity secret for wallet creation
     */
    function updateEntitySecret(bytes32 _newSecret) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        entitySecretCiphertext = _newSecret;
    }
    
    /**
     * @notice Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}