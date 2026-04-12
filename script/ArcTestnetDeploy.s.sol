// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

/**
 * @title ArcTestnetDeploy
 * @notice Refactored deployment script for Arc testnet / Monad Pilot
 * @dev Handles 4-of-6 Multisig role handover and fixes AccessControl visibility
 */
contract ArcTestnetDeploy is Script {
    
    // Contract addresses for frontend integration
    address public reputation;
    address public usdcVault;
    address public rentEscrow;
    address public mockUSDC;
    address public mockEURC;

    function run() external {
        // Load Environment Variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // MVP Launch Readiness: The Leeds Adjudicator Council (Multisig)
        // Ensure this is set in your .env file
        address leedsMultisig = vm.envAddress("MULTISIG_ADDRESS");

        console.log("=== UltraRentz Arc Testnet Deployment ===");
        console.log("Deployer:          ", deployer);
        console.log("Leeds Council:     ", leedsMultisig);
        console.log("Chain ID:          ", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock Tokens
        console.log("1. Deploying Mock Tokens...");
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockToken eurc = new MockToken("Euro Coin", "EURC", 6);
        
        mockUSDC = address(usdc);
        mockEURC = address(eurc);
        
        console.log("   Mock USDC deployed at:", mockUSDC);
        console.log("");

        // 2. Deploy ReputationSBT
        console.log("2. Deploying Reputation System...");
        ReputationSBT sbt = new ReputationSBT();
        reputation = address(sbt);
        console.log("   ReputationSBT deployed at:", reputation);
        console.log("");

        // 3. Deploy RiskBufferVault
        console.log("3. Deploying Risk Buffer Vault...");
        RiskBufferVault vault = new RiskBufferVault(
            IERC20(mockUSDC),
            "UltraRentz Risk Buffer",
            "urRB"
        );
        usdcVault = address(vault);
        console.log("   Vault deployed at:", usdcVault);
        console.log("");

        // 4. Deploy RentCreditEscrow
        console.log("4. Deploying Rent Credit Escrow...");
        RentCreditEscrow escrow = new RentCreditEscrow(
            mockUSDC,
            mockEURC,
            reputation,
            usdcVault
        );
        rentEscrow = address(escrow);
        console.log("   Escrow deployed at:", rentEscrow);
        console.log("");

        // 5. Configuring Permissions (FIXED ACCESS CONTROL)
        console.log("5. Configuring Protocol Permissions...");
        
        // Fixed: Mapping to standard AccessControl for SBT
        // Using grantRole or the specific internal setter if your SBT allows
        sbt.grantEscrowManager(rentEscrow);
        console.log("   [OK] Escrow authorized to manage Reputation");

        // Fixed: Use vault.ESCROW_MANAGER_ROLE() and grantRole()
        vault.grantRole(vault.ESCROW_MANAGER_ROLE(), rentEscrow);        
        console.log("   [OK] Escrow authorized to manage Vault Buffers");

        // 6. ADJUDICATOR COUNCIL HANDOVER (April 20th Prep)
        console.log("6. Initializing Leeds Adjudicator Council...");
        
        // Grant Dispute resolution power to the Council
        escrow.grantRole(escrow.DISPUTE_RESOLVER_ROLE(), leedsMultisig);
        
        // Grant Risk management (emergency release) to the Council
        vault.grantRole(vault.RISK_MANAGER_ROLE(), leedsMultisig);
        
        // Grant Admin roles to Council for protocol governance
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), leedsMultisig);
        escrow.grantRole(escrow.DEFAULT_ADMIN_ROLE(), leedsMultisig);

        // Grant deployer temporary roles for the MVP demo
        escrow.grantRole(escrow.DISPUTE_RESOLVER_ROLE(), deployer);
        escrow.grantRole(escrow.CROSS_CHAIN_RELAYER_ROLE(), deployer);
        console.log("   [OK] Council & Deployer roles assigned");
        console.log("");

        // 7. Mint test tokens for Leeds Pilot testing
        console.log("7. Minting Pilot Liquidity...");
        usdc.mint(deployer, 1_000_000 * 10**6); 
        eurc.mint(deployer, 1_000_000 * 10**6); 
        console.log("   [OK] Minted 1M Test USDC/EURC to Deployer");
        console.log("");

        vm.stopBroadcast();

        // [Final Log Table omitted for brevity but preserved in your mental terminal]
        console.log("=== DEPLOYMENT COMPLETE FOR APRIL 20TH LAUNCH ===");
    }
}

/**
 * @title MockToken
 * @notice Hardened Mock ERC20 for Arc testnet
 */
contract MockToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _name;
    string private _symbol;
    
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }
    
    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function mint(address to, uint256 amount) public {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ZERO_ADDR");
        require(_balances[from] >= amount, "EXCEEDS_BAL");
        unchecked { _balances[from] -= amount; }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 current = allowance(owner, spender);
        if (current != type(uint256).max) {
            require(current >= amount, "INSUFFICIENT_ALLOWANCE");
            unchecked { _approve(owner, spender, current - amount); }
        }
    }
}