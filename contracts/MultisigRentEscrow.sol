// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MultisigRentEscrow
 * @dev Extends escrow logic with multisig release functionality for rent deposits.
 * - Configurable signatories for tenants and landlords
 * - Quorum-based release (e.g., 4 of 6 signatures required)
 */
contract MultisigRentEscrow {
    struct Escrow {
        address[] signatories;
        uint256 quorum;
        uint256 balance;
        bool released;
        mapping(address => bool) signed;
        uint256 signatures;
    }

    mapping(uint256 => Escrow) public escrows;
    uint256 public nextEscrowId;

    event EscrowCreated(uint256 indexed escrowId, address[] signatories, uint256 quorum, uint256 amount);
    event DepositReleased(uint256 indexed escrowId);
    event Signed(uint256 indexed escrowId, address signer);

    /**
     * @dev Create a new escrow with signatories and quorum
     */
    function createEscrow(address[] memory signatories, uint256 quorum) external payable returns (uint256) {
        require(msg.value > 0, "Deposit required");
        require(signatories.length >= quorum, "Quorum exceeds signatories");
        uint256 escrowId = nextEscrowId++;
        Escrow storage e = escrows[escrowId];
        e.signatories = signatories;
        e.quorum = quorum;
        e.balance = msg.value;
        emit EscrowCreated(escrowId, signatories, quorum, msg.value);
        return escrowId;
    }

    /**
     * @dev Sign to approve release. Only signatories can sign.
     */
    function signRelease(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];
        require(!e.released, "Already released");
        bool isSigner = false;
        for (uint256 i = 0; i < e.signatories.length; i++) {
            if (e.signatories[i] == msg.sender) {
                isSigner = true;
                break;
            }
        }
        require(isSigner, "Not a signatory");
        require(!e.signed[msg.sender], "Already signed");
        e.signed[msg.sender] = true;
        e.signatures++;
        emit Signed(escrowId, msg.sender);
        if (e.signatures >= e.quorum) {
            releaseDeposit(escrowId);
        }
    }

    /**
     * @dev Release deposit if quorum reached
     */
    function releaseDeposit(uint256 escrowId) internal {
        Escrow storage e = escrows[escrowId];
        require(!e.released, "Already released");
        require(e.signatures >= e.quorum, "Quorum not reached");
        e.released = true;
        payable(msg.sender).transfer(e.balance);
        emit DepositReleased(escrowId);
    }

    /**
     * @dev Get escrow info
     */
    function getEscrow(uint256 escrowId) external view returns (
        address[] memory signatories,
        uint256 quorum,
        uint256 balance,
        bool released,
        uint256 signatures
    ) {
        Escrow storage e = escrows[escrowId];
        return (e.signatories, e.quorum, e.balance, e.released, e.signatures);
    }
}
