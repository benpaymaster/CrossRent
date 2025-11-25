// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/RentCreditEscrow.sol";
import "../contracts/ReputationSBT.sol";
import "../contracts/RiskBufferVault.sol";

/**
 * @title DevControlledDeploy
 * @notice Deployment script using organizer-provided dev wallet for hackathon demo
 * @dev Uses specific dev private key provided by organizers for consistent demo experience
 */
contract DevControlledDeploy is Script {
    
    // Dev-controlled wallet address (derived from organizer's private key)
    // This will be the address that receives all test tokens and manages contracts
    address public constant DEV_WALLET = 0x742d35cC6634C0532925a3B8D4caF4E2f27b2c8A; // Example - replace with actual
    
    // Contract addresses that will be deployed
    address public reputation;
    address public usdcVault;
    address public rentEscrow;
    address public mockUSDC;
    address public mockEURC;

    function run() external {
        // Use dev-controlled private key from environment
        uint256 devPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        address devWallet = vm.addr(devPrivateKey);
        
        // Verify we're using the expected dev wallet
        require(devWallet == DEV_WALLET, "Private key doesn't match expected dev wallet");

        console.log("=== CrossRent Dev-Controlled Deployment ===");
        console.log("Dev Wallet:", devWallet);
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        console.log("");

        vm.startBroadcast(devPrivateKey);

        // Deploy Mock USDC for Arc testnet
        console.log("1. Deploying Mock Tokens...");
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockToken eurc = new MockToken("Euro Coin", "EURC", 6);
        
        mockUSDC = address(usdc);
        mockEURC = address(eurc);
        
        console.log("   Mock USDC deployed at:", mockUSDC);
        console.log("   Mock EURC deployed at:", mockEURC);
        console.log("");

        // Deploy ReputationSBT
        console.log("2. Deploying Reputation System...");
        ReputationSBT sbt = new ReputationSBT();
        reputation = address(sbt);
        console.log("   ReputationSBT deployed at:", reputation);
        console.log("");

        // Deploy USDC Vault
        console.log("3. Deploying USDC Yield Vault...");
        RiskBufferVault vault = new RiskBufferVault(
            IERC20(mockUSDC),
            "CrossRent USDC Vault",
            "xrUSDC"
        );
        usdcVault = address(vault);
        console.log("   USDC Vault deployed at:", usdcVault);
        console.log("");

        // Deploy RentCreditEscrow
        console.log("4. Deploying Rent Credit Escrow...");
        RentCreditEscrow escrow = new RentCreditEscrow(
            mockUSDC,
            mockEURC,
            reputation,
            usdcVault
        );
        rentEscrow = address(escrow);
        console.log("   RentCreditEscrow deployed at:", rentEscrow);
        console.log("");

        // Configure permissions
        console.log("5. Configuring Permissions...");
        
        // Allow escrow to manage SBT reputation
        sbt.grantEscrowManager(rentEscrow);
        console.log("   [OK] Escrow granted SBT management permissions");

        // Allow escrow to manage vault
        vault.grantEscrowManager(rentEscrow);
        console.log("   [OK] Escrow granted vault management permissions");

        // Grant dev wallet admin roles
        escrow.grantRole(escrow.DISPUTE_RESOLVER_ROLE(), devWallet);
        escrow.grantRole(escrow.CROSS_CHAIN_RELAYER_ROLE(), devWallet);
        vault.grantRole(vault.RISK_MANAGER_ROLE(), devWallet);
        
        console.log("   [OK] Dev wallet granted admin roles");
        console.log("");

        // Mint test tokens to dev wallet
        console.log("6. Minting Test Tokens to Dev Wallet...");
        usdc.mint(devWallet, 10000000 * 10**6); // 10M USDC
        eurc.mint(devWallet, 10000000 * 10**6); // 10M EURC
        console.log("   [OK] Minted 10,000,000 USDC to dev wallet");
        console.log("   [OK] Minted 10,000,000 EURC to dev wallet");
        console.log("");

        // Also mint tokens to some demo addresses for testing
        console.log("7. Setting up Demo Addresses...");
        address[] memory demoAddresses = new address[](3);
    demoAddresses[0] = address(0x1234567890123456789012345678901234567890); // Demo tenant
    demoAddresses[1] = address(0x0987654321098765432109876543210987654321); // Demo landlord
    demoAddresses[2] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Demo user
        
        for (uint i = 0; i < demoAddresses.length; i++) {
            usdc.mint(demoAddresses[i], 1000000 * 10**6); // 1M USDC each
            eurc.mint(demoAddresses[i], 1000000 * 10**6); // 1M EURC each
            console.log("   [OK] Minted 1M tokens to demo address:", demoAddresses[i]);
        }
        console.log("");

        vm.stopBroadcast();

        console.log("=== DEV-CONTROLLED DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("[CONTRACT ADDRESSES FOR FRONTEND]");
        console.log("Copy these addresses to frontend/index.html:");
        console.log("");
        console.log("const CONTRACT_ADDRESSES = {");
        console.log("    RentCreditEscrow: \"", rentEscrow, "\",");
        console.log("    ReputationSBT: \"", reputation, "\",");
        console.log("    RiskBufferVault: \"", usdcVault, "\",");
        console.log("    USDC: \"", mockUSDC, "\",");
        console.log("    EURC: \"", mockEURC, "\"");
        console.log("};");
        console.log("");
        console.log("[DEV WALLET INFO]");
        console.log("Dev Wallet Address:", devWallet);
        console.log("USDC Balance: 10,000,000 USDC");
        console.log("EURC Balance: 10,000,000 EURC");
        console.log("");
        console.log("[DEMO SETUP]");
        console.log("- Contracts deployed and configured");
        console.log("- Dev wallet has admin permissions");
        console.log("- Test tokens minted to dev wallet and demo addresses");
        console.log("- Ready for hackathon demonstration");
        console.log("");
        console.log("CrossRent is now live with dev-controlled wallet!");
    }
}

/**
 * @title MockToken
 * @notice Mock ERC20 token for testing with dev-controlled minting
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
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function mint(address to, uint256 amount) public {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;
        
        emit Transfer(from, to, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}