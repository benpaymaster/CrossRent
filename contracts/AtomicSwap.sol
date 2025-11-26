// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AtomicSwap
 * @notice Trustless ERC20-to-ERC20 swaps using Hash Time-Locked Contracts (HTLC)
 */
contract AtomicSwap {
    using SafeERC20 for IERC20;

    struct Swap {
        address initiator;
        address participant;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        bytes32 secretHash;
        uint256 expiry;
        bool redeemed;
        bool refunded;
    }

    mapping(bytes32 => Swap) public swaps;

    event SwapInitiated(
        bytes32 indexed swapId,
        address indexed initiator,
        address indexed participant,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bytes32 secretHash,
        uint256 expiry
    );
    event SwapRedeemed(bytes32 indexed swapId, bytes32 secret);
    event SwapRefunded(bytes32 indexed swapId);

    /**
     * @notice Initiate a swap
     */
    function initiateSwap(
        address participant,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (bytes32 swapId) {
        require(expiry > block.timestamp, "Expiry must be in future");
        swapId = keccak256(
            abi.encodePacked(
                msg.sender,
                participant,
                tokenA,
                tokenB,
                amountA,
                amountB,
                secretHash,
                expiry
            )
        );
        require(swaps[swapId].initiator == address(0), "Swap already exists");
        swaps[swapId] = Swap({
            initiator: msg.sender,
            participant: participant,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            secretHash: secretHash,
            expiry: expiry,
            redeemed: false,
            refunded: false
        });
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        emit SwapInitiated(
            swapId,
            msg.sender,
            participant,
            tokenA,
            tokenB,
            amountA,
            amountB,
            secretHash,
            expiry
        );
    }

    /**
     * @notice Redeem a swap with the secret
     */
    function redeemSwap(bytes32 swapId, bytes32 secret) external {
        Swap storage swap = swaps[swapId];
        require(!swap.redeemed && !swap.refunded, "Already completed");
        require(swap.participant == msg.sender, "Not participant");
        require(
            keccak256(abi.encodePacked(secret)) == swap.secretHash,
            "Invalid secret"
        );
        require(block.timestamp <= swap.expiry, "Swap expired");
        swap.redeemed = true;
        IERC20(swap.tokenA).safeTransfer(swap.participant, swap.amountA);
        IERC20(swap.tokenB).safeTransferFrom(
            swap.participant,
            swap.initiator,
            swap.amountB
        );
        emit SwapRedeemed(swapId, secret);
    }

    /**
     * @notice Refund swap after expiry
     */
    function refundSwap(bytes32 swapId) external {
        Swap storage swap = swaps[swapId];
        require(!swap.redeemed && !swap.refunded, "Already completed");
        require(block.timestamp > swap.expiry, "Not expired");
        require(swap.initiator == msg.sender, "Not initiator");
        swap.refunded = true;
        IERC20(swap.tokenA).safeTransfer(swap.initiator, swap.amountA);
        emit SwapRefunded(swapId);
    }
}
