// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MultisigRentEscrow
 * @dev Extends escrow logic with multisig release functionality for rent deposits.
 * - Configurable signatories for tenants and landlords
 * - Quorum-based release (e.g., 4 of 6 signatures required)
 *
 * ## Engineering Notes
 * - Gas optimized: minimal storage, custom errors, efficient multisig logic
 * - Security: strict signatory checks, transparent event emission
 */
contract MultisigRentEscrow is ERC721 {
    error DepositRequired();
    error InvalidSignatoryCount();
    error InvalidQuorum();
    error AlreadyReleased();
    error NotSignatory();
    error AlreadySigned();
    error NotAuthorized();
    struct Escrow {
        address renter;
        address landlord;
        address[] renterSignatories;
        address[] landlordSignatories;
        uint256 quorum;
        uint256 balance;
        bool released;
        mapping(address => bool) signed;
        uint256 signatures;
        uint256 inventoryNftId;
        bool multisigConfirmed;
    }

    constructor() ERC721("PropertyInventory", "INVENTORY") {}

    mapping(uint256 => Escrow) public escrows;
    uint256 public nextEscrowId;
    uint256 public nftCount;
    mapping(uint256 => string) public inventoryMetadata;

    event MultisigSetup(
        uint256 indexed escrowId,
        address[] renterSignatories,
        address[] landlordSignatories
    );
    event InventoryNFTMinted(
        uint256 indexed escrowId,
        uint256 nftId,
        address to,
        string metadata
    );
    event MultisigConfirmed(uint256 indexed escrowId);
    event EscrowCreated(
        uint256 indexed escrowId,
        address[] renterSignatories,
        address[] landlordSignatories,
        uint256 quorum,
        uint256 amount
    );
    event DepositReleased(uint256 indexed escrowId);
    event Signed(uint256 indexed escrowId, address signer);

    /**
     * @dev Create a new escrow with signatories and quorum
     */
    function createEscrow(
        address landlord,
        address[] calldata renterSignatories,
        address[] calldata landlordSignatories,
        uint256 quorum,
        string calldata inventoryMetadataUri
    ) external payable returns (uint256) {
        if (msg.value == 0) revert DepositRequired();
        if (renterSignatories.length != 3 || landlordSignatories.length != 3)
            revert InvalidSignatoryCount();
        if (quorum != 4) revert InvalidQuorum();
        uint256 escrowId = nextEscrowId++;
        Escrow storage e = escrows[escrowId];
        e.renter = msg.sender;
        e.landlord = landlord;
        e.renterSignatories = renterSignatories;
        e.landlordSignatories = landlordSignatories;
        e.quorum = quorum;
        e.balance = msg.value;
        // Mint NFT to renter and landlord
        nftCount++;
        _mint(msg.sender, nftCount);
        inventoryMetadata[nftCount] = inventoryMetadataUri;
        e.inventoryNftId = nftCount;
        emit InventoryNFTMinted(
            escrowId,
            nftCount,
            msg.sender,
            inventoryMetadataUri
        );
        nftCount++;
        _mint(landlord, nftCount);
        inventoryMetadata[nftCount] = inventoryMetadataUri;
        emit InventoryNFTMinted(
            escrowId,
            nftCount,
            landlord,
            inventoryMetadataUri
        );
        emit MultisigSetup(escrowId, renterSignatories, landlordSignatories);
        emit EscrowCreated(
            escrowId,
            renterSignatories,
            landlordSignatories,
            quorum,
            msg.value
        );
        return escrowId;
    }

    /**
     * @dev Sign to approve release. Only signatories can sign.
     */
    function signRelease(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];
        if (e.released) revert AlreadyReleased();
        bool isSigner = false;
        uint256 lenR = e.renterSignatories.length;
        uint256 lenL = e.landlordSignatories.length;
        for (uint256 i = 0; i < lenR; ++i) {
            if (e.renterSignatories[i] == msg.sender) {
                isSigner = true;
                break;
            }
        }
        if (!isSigner) {
            for (uint256 i = 0; i < lenL; ++i) {
                if (e.landlordSignatories[i] == msg.sender) {
                    isSigner = true;
                    break;
                }
            }
        }
        if (!isSigner) revert NotSignatory();
        if (e.signed[msg.sender]) revert AlreadySigned();
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
        if (e.released) revert AlreadyReleased();
        if (e.signatures < e.quorum) revert InvalidQuorum();
        e.released = true;
        payable(msg.sender).transfer(e.balance);
        emit DepositReleased(escrowId);
    }

    /**
     * @dev Get escrow info
     */
    function confirmMultisig(uint256 escrowId) external {
        Escrow storage e = escrows[escrowId];
        if (!(msg.sender == e.renter || msg.sender == e.landlord))
            revert NotAuthorized();
        e.multisigConfirmed = true;
        emit MultisigConfirmed(escrowId);
    }

    function getEscrow(
        uint256 escrowId
    )
        external
        view
        returns (
            address renter,
            address landlord,
            address[] memory renterSignatories,
            address[] memory landlordSignatories,
            uint256 quorum,
            uint256 balance,
            bool released,
            uint256 signatures,
            uint256 inventoryNftId,
            bool multisigConfirmed
        )
    {
        Escrow storage e = escrows[escrowId];
        return (
            e.renter,
            e.landlord,
            e.renterSignatories,
            e.landlordSignatories,
            e.quorum,
            e.balance,
            e.released,
            e.signatures,
            e.inventoryNftId,
            e.multisigConfirmed
        );
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return inventoryMetadata[tokenId];
    }
}
