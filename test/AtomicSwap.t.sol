// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/AtomicSwap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AtomicSwapTest is Test {
    AtomicSwap swap;
    MockToken tokenA;
    MockToken tokenB;
    address alice = address(0xA);
    address bob = address(0xB);
    bytes32 secret = keccak256("supersecret");
    bytes32 secretHash = keccak256(abi.encodePacked(secret));
    uint256 expiry;

    function setUp() public {
        swap = new AtomicSwap();
        tokenA = new MockToken("TokenA", "TKA");
        tokenB = new MockToken("TokenB", "TKB");
        tokenA.mint(alice, 1000 ether);
        tokenB.mint(bob, 1000 ether);
        expiry = block.timestamp + 1 days;
    }

    function testInitiateAndRedeemSwap() public {
        vm.startPrank(alice);
        tokenA.approve(address(swap), 100 ether);
        bytes32 swapId = swap.initiateSwap(
            bob,
            address(tokenA),
            address(tokenB),
            100 ether,
            50 ether,
            secretHash,
            expiry
        );
        vm.stopPrank();

        vm.startPrank(bob);
        tokenB.approve(address(swap), 50 ether);
        swap.redeemSwap(swapId, secret);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(bob), 100 ether);
        assertEq(tokenB.balanceOf(alice), 50 ether);
    }

    function testRefundSwapAfterExpiry() public {
        vm.startPrank(alice);
        tokenA.approve(address(swap), 100 ether);
        bytes32 swapId = swap.initiateSwap(
            bob,
            address(tokenA),
            address(tokenB),
            100 ether,
            50 ether,
            secretHash,
            expiry
        );
        vm.stopPrank();

        vm.warp(expiry + 1);
        vm.startPrank(alice);
        swap.refundSwap(swapId);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(alice), 1000 ether);
    }
}
