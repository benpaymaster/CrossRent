// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/AtomicSwap.sol";
import "../contracts/CrossRentBridge.sol";
import "../contracts/AtomicSwapBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockCircleBridge is ICircleBridge {
    uint64 public lastNonce;

    function depositForBurn(
        uint256,
        uint32,
        bytes32,
        address
    ) external override returns (uint64 nonce) {
        lastNonce++;
        return lastNonce;
    }

    function replaceDepositForBurn(
        bytes calldata,
        bytes calldata,
        bytes32,
        bytes32
    ) external override {}

    function receiveMessage(
        bytes memory,
        bytes memory
    ) external pure override returns (bool) {
        return true;
    }

    function localDomain() external pure override returns (uint32) {
        return 0;
    }

    function version() external pure override returns (uint32) {
        return 1;
    }

    function usedNonces(bytes32) external pure override returns (bool) {
        return false;
    }
}

contract AtomicSwapBridgeTest is Test {
    AtomicSwap atomicSwap;
    CrossRentBridge bridge;
    AtomicSwapBridge swapBridge;
    MockToken tokenA;
    MockToken tokenB;
    MockCircleBridge circleBridge;
    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);
    uint256 chainId = 9999;
    uint32 domain = 42;
    bytes32 secret = keccak256("supersecret");
    bytes32 secretHash = keccak256(abi.encodePacked(secret));
    uint256 expiry;

    function setUp() public {
        atomicSwap = new AtomicSwap();
        tokenA = new MockToken("TokenA", "TKA");
        tokenB = new MockToken("TokenB", "TKB");
        circleBridge = new MockCircleBridge();
        bridge = new CrossRentBridge(
            address(circleBridge),
            address(0x2),
            address(tokenB),
            address(0x3),
            admin
        );
        swapBridge = new AtomicSwapBridge(address(atomicSwap), address(bridge));
        vm.prank(admin);
        bridge.addSupportedToken(address(tokenB));
        vm.prank(admin);
        bridge.addChainDomain(chainId, domain);
        tokenA.mint(alice, 1000 ether);
        tokenB.mint(bob, 1000 ether);
        expiry = block.timestamp + 1 days;
    }

    function testSwapAndBridge() public {
        vm.startPrank(alice);
        tokenA.approve(address(atomicSwap), 100 ether);
        bytes32 swapId = atomicSwap.initiateSwap(
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
        tokenB.approve(address(atomicSwap), 50 ether);
        atomicSwap.redeemSwap(swapId, secret);
        vm.stopPrank();

        // Alice should have received 50 tokenB from swap
        assertEq(tokenB.balanceOf(alice), 50 ether);

        vm.startPrank(alice);
        tokenB.approve(address(bridge), 50 ether);
        uint64 nonce = bridge.bridgeTokens(
            address(tokenB),
            50 ether,
            chainId,
            bob
        );
        vm.stopPrank();

        // After bridging, Alice's tokenB balance should be 0
        assertEq(tokenB.balanceOf(alice), 0);
        assertGt(nonce, 0);
        assertEq(tokenA.balanceOf(bob), 100 ether);
    }
}
