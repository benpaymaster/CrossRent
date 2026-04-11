// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../contracts/RiskBufferVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000e6); // 1M USDC
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract RiskBufferVaultTest is Test {
    RiskBufferVault vault;
    MockUSDC usdc;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address escrowManager = makeAddr("escrowManager");
    address riskManager = makeAddr("riskManager");
    address admin = makeAddr("admin");
    
    uint256 constant BUFFER_AMOUNT = 1000e6; // $1000
    uint256 constant ESCROW_ID = 1;
    
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
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Deploy vault
        vault = new RiskBufferVault(usdc, "RentCredit Risk Buffer", "RCRB");
        
        // Setup roles
        vault.grantEscrowManager(escrowManager);
        vault.grantRole(vault.RISK_MANAGER_ROLE(), riskManager);
        
        // Mint USDC to users
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        usdc.mint(escrowManager, 50000e6);
        
        vm.stopPrank();
        
        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        
        vm.prank(escrowManager);
        usdc.approve(address(vault), type(uint256).max);
    }
    
    function test_LockBuffer_Success() public {
        vm.startPrank(escrowManager);
        
        vm.expectEmit(true, true, true, false);
        emit BufferLocked(1, ESCROW_ID, escrowManager, BUFFER_AMOUNT, 0);
        
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        // Check buffer lock data
        RiskBufferVault.BufferLock memory lock = vault.getBufferLock(1);
        assertEq(lock.amount, BUFFER_AMOUNT);
        assertEq(lock.escrowId, ESCROW_ID);
        assertEq(lock.escrowAddress, escrowManager);
        assertFalse(lock.released);
        
        // Check risk metrics
        RiskBufferVault.RiskMetrics memory metrics = vault.getRiskMetrics();
        assertEq(metrics.totalLocked, BUFFER_AMOUNT);
        
        // Check USDC transfer
        assertEq(usdc.balanceOf(address(vault)), BUFFER_AMOUNT);
        assertEq(usdc.balanceOf(escrowManager), 50000e6 - BUFFER_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_LockBuffer_MinimumAmount() public {
        vm.startPrank(escrowManager);
        
        uint256 tooSmall = vault.MINIMUM_BUFFER_AMOUNT() - 1;
        
        vm.expectRevert("Amount too small");
        vault.lockBuffer(ESCROW_ID, tooSmall);
        
        vm.stopPrank();
    }
    
    function test_LockBuffer_ExceedsIndividualLimit() public {
        vm.startPrank(escrowManager);
        
        uint256 tooLarge = vault.maxIndividualLock() + 1;
        
        vm.expectRevert("Amount exceeds individual limit");
        vault.lockBuffer(ESCROW_ID, tooLarge);
        
        vm.stopPrank();
    }
    
    function test_ReleaseBuffer_Success() public {
        // Lock buffer first
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.startPrank(escrowManager);
        
        vm.expectEmit(true, true, false, false);
        emit BufferReleased(1, ESCROW_ID, BUFFER_AMOUNT, false);
        
        vault.releaseBuffer(ESCROW_ID);
        
        // Check buffer released
        RiskBufferVault.BufferLock memory lock = vault.getBufferLock(1);
        assertTrue(lock.released);
        
        // Check risk metrics updated
        RiskBufferVault.RiskMetrics memory metrics = vault.getRiskMetrics();
        assertEq(metrics.totalReleased, BUFFER_AMOUNT);
        assertEq(metrics.totalLocked, 0);
        
        // Check USDC returned
        assertEq(usdc.balanceOf(escrowManager), 50000e6);
        
        vm.stopPrank();
    }
    
    function test_ClaimBuffer_Partial() public {
        // Lock buffer first
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.startPrank(escrowManager);
        
        uint256 claimAmount = 300e6; // $300 claim
        
        vault.claimBuffer(ESCROW_ID, claimAmount, alice);
        
        // Check buffer amount reduced
        RiskBufferVault.BufferLock memory lock = vault.getBufferLock(1);
        assertEq(lock.amount, BUFFER_AMOUNT - claimAmount);
        assertFalse(lock.released); // Not fully released
        
        // Check claim went to alice
        assertEq(usdc.balanceOf(alice), 10000e6 + claimAmount);
        
        // Check risk metrics
        RiskBufferVault.RiskMetrics memory metrics = vault.getRiskMetrics();
        assertEq(metrics.totalClaimed, claimAmount);
        assertEq(metrics.totalLocked, BUFFER_AMOUNT - claimAmount);
        
        vm.stopPrank();
    }
    
    function test_ClaimBuffer_Full() public {
        // Lock buffer first
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.startPrank(escrowManager);
        
        vault.claimBuffer(ESCROW_ID, BUFFER_AMOUNT, alice);
        
        // Check buffer fully claimed
        RiskBufferVault.BufferLock memory lock = vault.getBufferLock(1);
        assertEq(lock.amount, 0);
        assertTrue(lock.released);
        
        // Check full claim went to alice
        assertEq(usdc.balanceOf(alice), 10000e6 + BUFFER_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_EmergencyReleaseBuffer() public {
        // Lock buffer first
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.startPrank(riskManager);
        
        uint256 penalty = (BUFFER_AMOUNT * vault.EMERGENCY_WITHDRAW_PENALTY()) / 10000;
        uint256 expectedRelease = BUFFER_AMOUNT - penalty;
        
        vault.emergencyReleaseBuffer(1);
        
        // Check emergency unlock
        assertTrue(vault.emergencyUnlocked(1));
        
        // Check penalty applied
        assertEq(usdc.balanceOf(escrowManager), 50000e6 - penalty);
        
        vm.stopPrank();
    }
    
    function test_DepositAndWithdraw() public {
        vm.startPrank(alice);
        
        uint256 depositAmount = 5000e6; // $5000
        
        // Deposit into vault
        uint256 shares = vault.deposit(depositAmount, alice);
        assertTrue(shares > 0);
        
        assertEq(usdc.balanceOf(alice), 10000e6 - depositAmount);
        assertEq(vault.balanceOf(alice), shares);
        
        // Withdraw from vault
        uint256 withdrawAmount = 2000e6; // $2000
        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, alice, alice);
        assertTrue(sharesRedeemed > 0);
        
        assertEq(usdc.balanceOf(alice), 10000e6 - depositAmount + withdrawAmount);
        
        vm.stopPrank();
    }
    
    function test_MaxWithdraw_WithLockedBuffers() public {
        // Alice deposits into vault
        vm.prank(alice);
        vault.deposit(5000e6, alice);
        
        // Lock some buffers
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, 2000e6);
        
        uint256 maxWithdrawable = vault.maxWithdraw(alice);
        uint256 availableLiquidity = vault.getAvailableLiquidity();
        
        // Should be limited by available liquidity
        assertTrue(maxWithdrawable <= availableLiquidity);
    }
    
    function test_UtilizationRate() public {
        // Alice deposits 10000 USDC
        vm.prank(alice);
        vault.deposit(10000e6, alice);
        
        // Lock 2000 USDC buffer
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, 2000e6);
        
        RiskBufferVault.RiskMetrics memory metrics = vault.getRiskMetrics();
        // Utilization = locked / total assets * 10000
        // = 2000 / 12000 * 10000 = 1666.67 (16.67%)
        assertTrue(metrics.utilizationRate > 1600);
        assertTrue(metrics.utilizationRate < 1700);
    }
    
    function test_YieldStrategy() public {
        vm.startPrank(riskManager);
        
        vault.setYieldStrategy(
            true,     // enabled
            500,      // 5% APY
            8000,     // 80% max utilization
            1000,     // 10% rebalance threshold
            address(0) // no strategy contract
        );
        
        RiskBufferVault.YieldStrategy memory strategy = vault.getYieldStrategy();
        assertTrue(strategy.enabled);
        assertEq(strategy.targetApy, 500);
        assertEq(strategy.maxUtilization, 8000);
        
        vm.stopPrank();
    }
    
    function test_SetRiskParameters() public {
        vm.startPrank(riskManager);
        
        uint256 newMaxIndividual = 200000e6; // $200k
        uint256 newTotalLimit = 20000000e6; // $20M
        uint256 newReserveRatio = 2500; // 25%
        
        vault.setRiskParameters(newMaxIndividual, newTotalLimit, newReserveRatio);
        
        assertEq(vault.maxIndividualLock(), newMaxIndividual);
        assertEq(vault.totalRiskLimit(), newTotalLimit);
        assertEq(vault.liquidityReserveRatio(), newReserveRatio);
        
        vm.stopPrank();
    }
    
    function test_SetRiskParameters_ReserveRatioTooHigh() public {
        vm.startPrank(riskManager);
        
        vm.expectRevert("Reserve ratio too high");
        vault.setRiskParameters(100000e6, 10000000e6, 5001); // 50.01%
        
        vm.stopPrank();
    }
    
    function test_PlatformFeeSettings() public {
        vm.startPrank(admin);
        
        vault.setProtocolFeeRate(200); // 2%
        assertEq(vault.protocolFeeRate(), 200);
        
        vm.expectRevert("Fee rate too high");
        vault.setProtocolFeeRate(2001); // 20.01%
        
        vm.stopPrank();
    }
    
    function test_Pausable() public {
        vm.startPrank(admin);
        
        vault.pause();
        
        vm.stopPrank();
        
        // Try to lock buffer while paused
        vm.startPrank(escrowManager);
        
        vm.expectRevert();
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.stopPrank();
        
        // Try to deposit while paused
        vm.startPrank(alice);
        
        vm.expectRevert();
        vault.deposit(1000e6, alice);
        
        vm.stopPrank();
        
        // Unpause and try again
        vm.prank(admin);
        vault.unpause();
        
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
    }
    
    function test_EmergencyWithdraw() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(5000e6, alice);
        
        vm.startPrank(admin);
        
        uint256 withdrawAmount = 1000e6;
        vault.emergencyWithdraw(withdrawAmount);
        
        assertEq(usdc.balanceOf(admin), withdrawAmount);
        
        vm.stopPrank();
    }
    
    function test_OnlyAuthorizedCanLockBuffer() public {
        // Non-escrow manager cannot lock buffer
        vm.startPrank(alice);
        
        vm.expectRevert();
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_CannotReleaseOtherEscrowBuffer() public {
        // Alice (different escrow) locks buffer
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        // Bob (different escrow) cannot release
        vm.startPrank(bob);
        
        vm.expectRevert("Lock not found");
        vault.releaseBuffer(ESCROW_ID);
        
        vm.stopPrank();
    }
    
    function test_GetTotalValueLocked() public {
        vm.prank(escrowManager);
        vault.lockBuffer(ESCROW_ID, BUFFER_AMOUNT);
        
        uint256 tvl = vault.getTotalValueLocked();
        assertEq(tvl, BUFFER_AMOUNT);
    }
    
    function test_GetUserLocks() public {
        vm.startPrank(escrowManager);
        
        vault.lockBuffer(1, BUFFER_AMOUNT);
        vault.lockBuffer(2, BUFFER_AMOUNT);
        
        vm.stopPrank();
        
        uint256[] memory locks = vault.getUserLocks(escrowManager);
        assertEq(locks.length, 2);
        assertEq(locks[0], 1);
        assertEq(locks[1], 2);
    }
    
    function test_ERC4626Compliance() public {
        vm.startPrank(alice);
        
        // Test preview functions
        uint256 assets = 1000e6;
        uint256 previewShares = vault.previewDeposit(assets);
        uint256 actualShares = vault.deposit(assets, alice);
        assertEq(previewShares, actualShares);
        
        uint256 previewAssets = vault.previewRedeem(actualShares);
        uint256 actualAssets = vault.redeem(actualShares, alice, alice);
        
        // Should be close (allowing for rounding)
        assertTrue(actualAssets >= previewAssets - 1);
        assertTrue(actualAssets <= previewAssets + 1);
        
        vm.stopPrank();
    }
}
