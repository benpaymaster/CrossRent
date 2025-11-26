// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AtomicSwap.sol";
import "./CrossRentBridge.sol";

/**
 * @title AtomicSwapBridge
 * @notice Integrates AtomicSwap with CrossRentBridge for cross-chain atomic swaps
 */
contract AtomicSwapBridge {
    AtomicSwap public atomicSwap;
    CrossRentBridge public crossRentBridge;

    constructor(address _atomicSwap, address _crossRentBridge) {
        atomicSwap = AtomicSwap(_atomicSwap);
        crossRentBridge = CrossRentBridge(_crossRentBridge);
    }

    /**
     * @notice Initiate a swap and bridge tokens cross-chain
     * @dev Example: swap tokenA for tokenB, then bridge tokenB to another chain
     */
    function swapAndBridge(
        address participant,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bytes32 secretHash,
        uint256 expiry,
        uint256 destinationChainId,
        address recipient
    ) external returns (bytes32 swapId, uint64 bridgeNonce) {
        swapId = atomicSwap.initiateSwap(
            participant,
            tokenA,
            tokenB,
            amountA,
            amountB,
            secretHash,
            expiry
        );
        // After swap is redeemed, bridge tokenB to another chain
        // This is a simplified example; production logic should handle swap state and redemption
        bridgeNonce = crossRentBridge.bridgeTokens(
            tokenB,
            amountB,
            destinationChainId,
            recipient
        );
    }
}
