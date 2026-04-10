// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ICircleBridge.sol";
import "./interfaces/ICircleGateway.sol";

/**
 * @title CrossRentBridge
 * @notice Cross-chain rental bridge powered by Circle's Bridge Kit + CCTP
 * @dev Integrates Circle's Cross-Chain Transfer Protocol for seamless USDC/EURC transfers
 */
contract CrossRentBridge is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Circle Bridge Kit interfaces
    ICircleBridge public immutable CIRCLE_BRIDGE;
    ICircleGateway public immutable CIRCLE_GATEWAY;
    
    // Supported tokens
    IERC20 public immutable USDC;
    IERC20 public immutable EURC;
    
    // Domain mapping for CCTP
    mapping(uint256 => uint32) public chainIdToDomain;
    mapping(address => bool) public supportedTokens;
    
    // Escrow integration
    address public rentEscrowContract;
    
    struct CrossChainDeposit {
        uint256 escrowId;
        address depositor;
        address token;
        uint256 amount;
        uint32 destinationDomain;
        uint64 nonce;
        bool completed;
        bytes32 messageHash;
    }
    
    mapping(bytes32 => CrossChainDeposit) public deposits;
    mapping(uint256 => bytes32) public escrowToDeposit;
    
    event CrossChainDepositInitiated(
        bytes32 indexed depositId,
        uint256 indexed escrowId,
        address indexed depositor,
        address token,
        uint256 amount,
        uint32 destinationDomain
    );
    
    event CrossChainDepositCompleted(
        bytes32 indexed depositId,
        uint256 indexed escrowId,
        address recipient,
        uint256 amount
    );
    
    event TokenBridged(
        address indexed token,
        uint256 amount,
        uint32 destinationDomain,
        address recipient,
        uint64 nonce
    );

    error UnsupportedToken();
    error InvalidDomain();
    error DepositNotFound();
    error DepositAlreadyCompleted();
    error InsufficientBalance();
    error BridgeTransferFailed();

    constructor(
        address _CIRCLE_BRIDGE,
        address _CIRCLE_GATEWAY,
        address _usdc,
        address _eurc,
        address _admin
    ) {
        CIRCLE_BRIDGE = ICircleBridge(_CIRCLE_BRIDGE);
        CIRCLE_GATEWAY = ICircleGateway(_CIRCLE_GATEWAY);
        USDC = IERC20(_usdc);
        EURC = IERC20(_eurc);
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        
        // Mark tokens as supported
        supportedTokens[_usdc] = true;
        supportedTokens[_eurc] = true;
        
        // Initialize common domain mappings
        chainIdToDomain[1] = 0;      // Ethereum
        chainIdToDomain[137] = 7;    // Polygon
        chainIdToDomain[43114] = 1;  // Avalanche
        chainIdToDomain[42161] = 3;  // Arbitrum
        chainIdToDomain[10] = 2;     // Optimism
        chainIdToDomain[8453] = 6;   // Base
    }

    /**
     * @notice Initiate cross-chain deposit for rental escrow
     * @param escrowId The rental escrow ID on destination chain
     * @param token The token address (USDC or EURC)
     * @param amount Amount to transfer
     * @param destinationChainId Target chain ID
     * @param recipient Recipient address on destination chain
     */
    function initiateCrossChainDeposit(
        uint256 escrowId,
        address token,
        uint256 amount,
        uint256 destinationChainId,
        address recipient
    ) external nonReentrant returns (bytes32 depositId) {
        if (!supportedTokens[token]) revert UnsupportedToken();
        
        uint32 destinationDomain = chainIdToDomain[destinationChainId];
        if (destinationDomain == 0) revert InvalidDomain();
        
        // Generate unique deposit ID
        depositId = keccak256(
            abi.encodePacked(
                escrowId,
                msg.sender,
                token,
                amount,
                block.timestamp,
                block.number
            )
        );
        
        // Transfer tokens from depositor
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve Circle Bridge for transfer
        IERC20(token).approve(address(CIRCLE_BRIDGE), amount);
        
        // Initiate CCTP transfer
        uint64 nonce = CIRCLE_BRIDGE.depositForBurn(
            amount,
            destinationDomain,
            bytes32(uint256(uint160(recipient))), // Convert address to bytes32
            token
        );
        
        // Store deposit information
        deposits[depositId] = CrossChainDeposit({
            escrowId: escrowId,
            depositor: msg.sender,
            token: token,
            amount: amount,
            destinationDomain: destinationDomain,
            nonce: nonce,
            completed: false,
            messageHash: bytes32(0)
        });
        
        escrowToDeposit[escrowId] = depositId;
        
        emit CrossChainDepositInitiated(
            depositId,
            escrowId,
            msg.sender,
            token,
            amount,
            destinationDomain
        );
        
        emit TokenBridged(token, amount, destinationDomain, recipient, nonce);
        
        return depositId;
    }
    
    /**
     * @notice Complete cross-chain deposit (called by relayers)
     * @param depositId The deposit ID to complete
     * @param messageBytes The CCTP message bytes
     * @param signature The attestation signature
     */
    function completeCrossChainDeposit(
        bytes32 depositId,
        bytes memory messageBytes,
        bytes memory signature
    ) external onlyRole(RELAYER_ROLE) nonReentrant {
        CrossChainDeposit storage deposit = deposits[depositId];
        
        if (deposit.depositor == address(0)) revert DepositNotFound();
        if (deposit.completed) revert DepositAlreadyCompleted();
        
        // Receive tokens via Circle CCTP
        bool success = CIRCLE_BRIDGE.receiveMessage(messageBytes, signature);
        if (!success) revert BridgeTransferFailed();
        
        // Mark as completed
        deposit.completed = true;
        deposit.messageHash = keccak256(messageBytes);
        
        // Extract recipient address from message (this would be implementation specific)
        address recipient = address(0); // Placeholder - would extract from CCTP message
        
        emit CrossChainDepositCompleted(
            depositId,
            deposit.escrowId,
            recipient,
            deposit.amount
        );
    }
    
    /**
     * @notice Bridge tokens directly (for general use)
     * @param token Token to bridge (USDC or EURC)
     * @param amount Amount to bridge
     * @param destinationChainId Target chain
     * @param recipient Recipient on destination chain
     */
    function bridgeTokens(
        address token,
        uint256 amount,
        uint256 destinationChainId,
        address recipient
    ) external nonReentrant returns (uint64 nonce) {
        if (!supportedTokens[token]) revert UnsupportedToken();
        
        uint32 destinationDomain = chainIdToDomain[destinationChainId];
        if (destinationDomain == 0) revert InvalidDomain();
        
        // Transfer tokens from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve and bridge
        IERC20(token).forceApprove(address(CIRCLE_BRIDGE), amount);
        
        nonce = CIRCLE_BRIDGE.depositForBurn(
            amount,
            destinationDomain,
            bytes32(uint256(uint160(recipient))),
            token
        );
        
        emit TokenBridged(token, amount, destinationDomain, recipient, nonce);
        
        return nonce;
    }
    
    /**
     * @notice Emergency withdraw function
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    /**
     * @notice Set rental escrow contract
     */
    function setRentEscrowContract(address _escrow) external onlyRole(OPERATOR_ROLE) {
        rentEscrowContract = _escrow;
    }
    
    /**
     * @notice Add supported token
     */
    function addSupportedToken(address token) external onlyRole(OPERATOR_ROLE) {
        supportedTokens[token] = true;
    }
    
    /**
     * @notice Add chain domain mapping
     */
    function addChainDomain(uint256 chainId, uint32 domain) external onlyRole(OPERATOR_ROLE) {
        chainIdToDomain[chainId] = domain;
    }
    
    /**
     * @notice Check if deposit is completed
     */
    function isDepositCompleted(bytes32 depositId) external view returns (bool) {
        return deposits[depositId].completed;
    }
    
    /**
     * @notice Get deposit details
     */
    function getDeposit(bytes32 depositId) external view returns (CrossChainDeposit memory) {
        return deposits[depositId];
    }
    
    /**
     * @notice Get deposit by escrow ID
     */
    function getDepositByEscrow(uint256 escrowId) external view returns (CrossChainDeposit memory) {
        bytes32 depositId = escrowToDeposit[escrowId];
        return deposits[depositId];
    }
}