// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title ReputationSBT
 * @dev Soulbound Token (SBT) for tracking rental reputation and credit history.
 *      - Non-transferable ERC-721
 *      - Credit score (0–1000) based on rental performance, disputes, volume, and international activity
 *      - Designed for cross-border rental reputation in systems like CrossRent
 */
contract ReputationSBT is ERC721, AccessControl {
    using Strings for uint256;

    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");

    struct ReputationData {
        uint256 totalRentals;
        uint256 successfulRentals;
        uint256 totalValueLocked;      // in USDC (6 decimals)
        uint256 totalValueLockedEURC;  // in EURC (6 decimals) 
        uint256 averageRentAmount;
        uint256 timesDisputed;
        uint256 disputesWon;
        uint256 lastRentalTimestamp;
        uint256 joinedTimestamp;
        bool isLandlord;
        bool isTenant;
        uint256 creditScore;           // 0–1000 scale
        string[] countries;            // Countries/markets where user has rental history
    }

    struct TokenMetrics {
        uint256 usdcVolume;
        uint256 eurcVolume;
        uint256 usdcRentals;
        uint256 eurcRentals;
        uint256 crossCurrencyBonus; // Bonus points for using multiple stablecoins
    }

    struct RentalRecord {
        uint256 escrowId;
        address counterparty;
        uint256 amount;        // USDC (6 decimals)
        uint256 timestamp;
        bool successful;
        bool wasDisputed;
        string propertyLocation; // can represent city/country/region
        uint256 duration;      // seconds or days (up to you in escrow)
    }

    // Core mappings
    mapping(address => ReputationData) public reputation;
    mapping(address => TokenMetrics) public tokenMetrics;
    mapping(address => RentalRecord[]) public rentalHistory;
    mapping(address => uint256) public tokenIds; // user address → token ID
    mapping(address => bool) public hasToken;

    uint256 private _nextTokenId = 1;
    uint256 public constant MAX_CREDIT_SCORE = 1000;
    uint256 public constant MIN_CREDIT_SCORE = 0;

    // ---------------------------------------
    // Events
    // ---------------------------------------

    event ReputationTokenMinted(address indexed user, uint256 indexed tokenId);
    event ReputationUpdated(
        address indexed user,
        uint256 newCreditScore,
        uint256 totalRentals,
        uint256 successfulRentals
    );

    event RentalRecordAdded(
        address indexed user,
        uint256 indexed escrowId,
        uint256 amount,
        bool successful
    );

    event RolesUpdated(address indexed user, bool isLandlord, bool isTenant);

    constructor() ERC721("RentCredit Reputation", "RCR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ---------------------------------------
    // Minting & Initialization
    // ---------------------------------------

    /**
     * @notice Mints a new reputation SBT for a user if they don't already have one.
     * @dev SBT is non-transferable; one token per user.
     */
    function mintReputationToken(address to) public returns (uint256) {
        require(!hasToken[to], "ReputationSBT: user already has token");
        require(to != address(0), "ReputationSBT: invalid address");

        uint256 tokenId = _nextTokenId++;
        tokenIds[to] = tokenId;
        hasToken[to] = true;

        // Initialize reputation data
        reputation[to] = ReputationData({
            totalRentals: 0,
            successfulRentals: 0,
            totalValueLocked: 0,
            totalValueLockedEURC: 0,
            averageRentAmount: 0,
            timesDisputed: 0,
            disputesWon: 0,
            lastRentalTimestamp: 0,
            joinedTimestamp: block.timestamp,
            isLandlord: false,
            isTenant: false,
            creditScore: 500, // neutral starting score
            countries: new string[](0)
        });

        // Initialize token metrics
        tokenMetrics[to] = TokenMetrics({
            usdcVolume: 0,
            eurcVolume: 0,
            usdcRentals: 0,
            eurcRentals: 0,
            crossCurrencyBonus: 0
        });

        _mint(to, tokenId);

        emit ReputationTokenMinted(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Ensures a user has an SBT; mint if missing.
     */
    function _ensureToken(address user) internal {
        if (!hasToken[user]) {
            mintReputationToken(user);
        }
    }

    // ---------------------------------------
    // Reputation & Rental Updates (Escrow)
    // ---------------------------------------

    /**
     * @notice Updates rental aggregates and recalculates credit score with token tracking.
     * @dev Enhanced version that tracks USDC vs EURC usage separately
     * @param user       Tenant or landlord
     * @param amount     Token amount involved in the rental
     * @param successful Whether the rental was considered successful for this user
     * @param token      Address of the token used (USDC or EURC)
     */
    function updateRentalHistoryWithToken(
        address user,
        uint256 amount,
        bool successful,
        address token
    ) external onlyRole(ESCROW_MANAGER_ROLE) {
        _ensureToken(user);

        ReputationData storage rep = reputation[user];
        TokenMetrics storage metrics = tokenMetrics[user];

        // Basic stats
        rep.totalRentals += 1;
        if (successful) {
            rep.successfulRentals += 1;
        }

        // Update token-specific metrics
        if (token == 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85) { // USDC on Optimism
            rep.totalValueLocked += amount;
            metrics.usdcVolume += amount;
            metrics.usdcRentals += 1;
        } else { // Assume EURC or other
            rep.totalValueLockedEURC += amount;
            metrics.eurcVolume += amount;
            metrics.eurcRentals += 1;
        }

        // Cross-currency bonus (using both USDC and EURC)
        if (metrics.usdcRentals > 0 && metrics.eurcRentals > 0) {
            metrics.crossCurrencyBonus = 50; // 50 point bonus for multi-token usage
        }

        rep.averageRentAmount = (rep.totalValueLocked + rep.totalValueLockedEURC) / rep.totalRentals;
        rep.lastRentalTimestamp = block.timestamp;

        // Recalculate credit score with multi-token bonus
        rep.creditScore = _calculateCreditScore(user);

        emit ReputationUpdated(user, rep.creditScore, rep.totalRentals, rep.successfulRentals);
    }

    /**
     * @notice Updates rental aggregates and recalculates credit score (legacy function).
     * @dev This is the function your Escrow already calls:
     *      - compatible with RentCreditEscrow.updateRentalHistory(...)
     * @param user       Tenant or landlord
     * @param amount     USDC amount involved in the rental
     * @param successful Whether the rental was considered successful for this user
     */
    function updateRentalHistory(
        address user,
        uint256 amount,
        bool successful
    ) external onlyRole(ESCROW_MANAGER_ROLE) {
        _ensureToken(user);

        ReputationData storage rep = reputation[user];
        TokenMetrics storage metrics = tokenMetrics[user];

        // Basic stats
        rep.totalRentals += 1;
        if (successful) {
            rep.successfulRentals += 1;
        }

        // Assume USDC for legacy function
        rep.totalValueLocked += amount;
        metrics.usdcVolume += amount;
        metrics.usdcRentals += 1;

        rep.averageRentAmount = (rep.totalValueLocked + rep.totalValueLockedEURC) / rep.totalRentals;
        rep.lastRentalTimestamp = block.timestamp;

        // Recalculate credit score
        rep.creditScore = _calculateCreditScore(user);

        emit ReputationUpdated(user, rep.creditScore, rep.totalRentals, rep.successfulRentals);
    }

    /**
     * @notice Adds a detailed rental record (for analytics / UI).
     * @dev Called by escrow contract when a rental completes or updates.
     */
    function addRentalRecord(
        address user,
        uint256 escrowId,
        address counterparty,
        uint256 amount,
        bool successful,
        bool wasDisputed,
        string calldata propertyLocation,
        uint256 duration
    ) external onlyRole(ESCROW_MANAGER_ROLE) {
        _ensureToken(user);

        rentalHistory[user].push(
            RentalRecord({
                escrowId: escrowId,
                counterparty: counterparty,
                amount: amount,
                timestamp: block.timestamp,
                successful: successful,
                wasDisputed: wasDisputed,
                propertyLocation: propertyLocation,
                duration: duration
            })
        );

        ReputationData storage rep = reputation[user];

        // Dispute stats
        if (wasDisputed) {
            rep.timesDisputed += 1;
            if (successful) {
                rep.disputesWon += 1;
            }
        }

        // Add country/market if new
        bool exists;
        for (uint256 i = 0; i < rep.countries.length; i++) {
            if (keccak256(bytes(rep.countries[i])) == keccak256(bytes(propertyLocation))) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            rep.countries.push(propertyLocation);
        }

        emit RentalRecordAdded(user, escrowId, amount, successful);
    }

    /**
     * @notice Convenience helper for escrow: update stats AND detailed record in one call.
     * @dev Optional for your escrow; you can keep calling the two functions separately if you prefer.
     */
    function updateHistoryWithRecord(
        address user,
        uint256 amount,
        bool successful,
        uint256 escrowId,
        address counterparty,
        bool wasDisputed,
        string calldata propertyLocation,
        uint256 duration
    ) external onlyRole(ESCROW_MANAGER_ROLE) {
        this.updateRentalHistory(user, amount, successful);
        this.addRentalRecord(user, escrowId, counterparty, amount, successful, wasDisputed, propertyLocation, duration);
    }

    /**
     * @notice Updates the user's role flags (landlord/tenant).
     */
    function updateUserRole(address user, bool isLandlord, bool isTenant)
        external
        onlyRole(ESCROW_MANAGER_ROLE)
    {
        _ensureToken(user);

        ReputationData storage rep = reputation[user];
        rep.isLandlord = isLandlord;
        rep.isTenant = isTenant;

        emit RolesUpdated(user, isLandlord, isTenant);
    }

    // ---------------------------------------
    // Scoring Logic
    // ---------------------------------------

    /**
     * @dev Calculates a credit score (0–1000) based on:
     *      - Success rate
     *      - Number of rentals
     *      - Total value locked (USDC + EURC)
     *      - Dispute frequency
     *      - International diversity
     *      - Time active
     *      - Multi-token usage bonus
     */
    function _calculateCreditScore(address user) internal view returns (uint256) {
        ReputationData memory rep = reputation[user];
        TokenMetrics memory metrics = tokenMetrics[user];

        if (rep.totalRentals == 0) {
            return 500; // Neutral starting score for fresh users
        }

        uint256 score = 500; // Base score

        // Success rate factor (0–300)
        uint256 successRate = (rep.successfulRentals * 100) / rep.totalRentals;
        score += successRate * 3; // 100% → +300

        // Experience factor (0–200)
        uint256 experiencePoints = rep.totalRentals * 10; // 10 pts per rental
        if (experiencePoints > 200) experiencePoints = 200;
        score += experiencePoints;

        // Volume factor (0–150): combined USDC + EURC volume
        uint256 totalVolume = rep.totalValueLocked + rep.totalValueLockedEURC;
        uint256 volumePoints = totalVolume / 1e8; // (1e6 * 100)
        if (volumePoints > 150) volumePoints = 150;
        score += volumePoints;

        // Multi-stablecoin bonus (0–75): bonus for using both USDC and EURC
        if (metrics.usdcRentals > 0 && metrics.eurcRentals > 0) {
            score += 50; // Base cross-currency bonus
            // Additional bonus based on balance between tokens
            uint256 minRentals = metrics.usdcRentals < metrics.eurcRentals ? metrics.usdcRentals : metrics.eurcRentals;
            uint256 balanceBonus = minRentals > 10 ? 25 : (minRentals * 25) / 10;
            score += balanceBonus;
        }

        // Dispute penalty (max -200)
        uint256 disputePenalty = rep.timesDisputed * 50;
        if (disputePenalty > 200) disputePenalty = 200;
        if (score > disputePenalty) {
            score -= disputePenalty;
        } else {
            score = 0;
        }

        // International experience bonus (0–100)
        uint256 internationalBonus = rep.countries.length * 20;
        if (internationalBonus > 100) internationalBonus = 100;
        score += internationalBonus;

        // Time active bonus (0–50)
        if (rep.joinedTimestamp > 0 && rep.joinedTimestamp < block.timestamp) {
            uint256 monthsActive = (block.timestamp - rep.joinedTimestamp) / (30 days);
            uint256 timeBonus = monthsActive;
            if (timeBonus > 50) timeBonus = 50;
            score += timeBonus;
        }

        // Clamp to [MIN_CREDIT_SCORE, MAX_CREDIT_SCORE]
        if (score > MAX_CREDIT_SCORE) score = MAX_CREDIT_SCORE;
        if (score < MIN_CREDIT_SCORE) score = MIN_CREDIT_SCORE;

        return score;
    }

    // ---------------------------------------
    // SVG + Metadata (Visual Wow Factor)
    // ---------------------------------------

    function _generateSVG(address user) internal view returns (string memory) {
        ReputationData memory rep = reputation[user];

        string memory scoreColor;
        if (rep.creditScore >= 800) scoreColor = "#10B981"; // Green
        else if (rep.creditScore >= 600) scoreColor = "#F59E0B"; // Yellow
        else scoreColor = "#EF4444"; // Red

        // Avoid division by zero
        uint256 successRate = rep.totalRentals > 0
            ? (rep.successfulRentals * 100) / rep.totalRentals
            : 0;

        string memory roleLabel = rep.isLandlord && rep.isTenant
            ? "Both"
            : rep.isLandlord
                ? "Landlord"
                : rep.isTenant
                    ? "Tenant"
                    : "New User";

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="600" viewBox="0 0 400 600">',
                '<defs><linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />',
                '</linearGradient></defs>',
                '<rect width="400" height="600" fill="url(#grad)" rx="20"/>',
                '<text x="200" y="60" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="white" text-anchor="middle">RentCredit</text>',
                '<text x="200" y="90" font-family="Arial, sans-serif" font-size="16" fill="white" text-anchor="middle">Reputation Score</text>',
                '<circle cx="200" cy="180" r="80" fill="none" stroke="white" stroke-width="4"/>',
                '<text x="200" y="195" font-family="Arial, sans-serif" font-size="48" font-weight="bold" fill="',
                scoreColor,
                '" text-anchor="middle">',
                rep.creditScore.toString(),
                "</text>",
                '<text x="50" y="320" font-family="Arial, sans-serif" font-size="14" fill="white">Total Rentals: ',
                rep.totalRentals.toString(),
                "</text>",
                '<text x="50" y="350" font-family="Arial, sans-serif" font-size="14" fill="white">Success Rate: ',
                successRate.toString(),
                "%</text>",
                '<text x="50" y="380" font-family="Arial, sans-serif" font-size="14" fill="white">Countries: ',
                rep.countries.length.toString(),
                "</text>",
                '<text x="50" y="410" font-family="Arial, sans-serif" font-size="14" fill="white">Total Value: $',
                (rep.totalValueLocked / 1e6).toString(),
                "</text>",
                '<text x="50" y="440" font-family="Arial, sans-serif" font-size="14" fill="white">Role: ',
                roleLabel,
                "</text>",
                '<text x="200" y="550" font-family="Arial, sans-serif" font-size="12" fill="white" text-anchor="middle">Soulbound - Non-transferable</text>',
                "</svg>"
            )
        );
    }

    /**
     * @dev Returns on-chain JSON metadata (data: URI) for the SBT.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ReputationSBT: token does not exist");

        address owner = _ownerOf(tokenId);
        ReputationData memory rep = reputation[owner];

        string memory svg = _generateSVG(owner);
        string memory image = string(
            abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg)))
        );

        uint256 successRate = rep.totalRentals > 0
            ? (rep.successfulRentals * 100) / rep.totalRentals
            : 0;

        string memory roleLabel = rep.isLandlord && rep.isTenant
            ? "Both"
            : rep.isLandlord
                ? "Landlord"
                : rep.isTenant
                    ? "Tenant"
                    : "New User";

        string memory attributes = string(
            abi.encodePacked(
                "[",
                '{"trait_type":"Credit Score","value":',
                rep.creditScore.toString(),
                "},",
                '{"trait_type":"Total Rentals","value":',
                rep.totalRentals.toString(),
                "},",
                '{"trait_type":"Success Rate","value":',
                successRate.toString(),
                "},",
                '{"trait_type":"Countries","value":',
                rep.countries.length.toString(),
                "},",
                '{"trait_type":"Role","value":"',
                roleLabel,
                '"},',
                '{"trait_type":"Member Since","value":',
                rep.joinedTimestamp.toString(),
                "}",
                "]"
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"RentCredit Reputation #',
                tokenId.toString(),
                '",',
                '"description":"Soulbound token representing rental reputation and credit history for cross-border rental transactions.",',
                '"image":"',
                image,
                '",',
                '"attributes":',
                attributes,
                "}"
            )
        );

        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json)))
        );
    }

    // ---------------------------------------
    // View Helpers for Frontend / UX
    // ---------------------------------------

    function getReputationScore(address user) external view returns (uint256) {
        if (!hasToken[user]) return 500; // default neutral score
        return reputation[user].creditScore;
    }

    function getReputationData(address user) external view returns (ReputationData memory) {
        return reputation[user];
    }

    function getTokenMetrics(address user) external view returns (TokenMetrics memory) {
        return tokenMetrics[user];
    }

    function getRentalHistory(address user) external view returns (RentalRecord[] memory) {
        return rentalHistory[user];
    }

    function getRentalCount(address user) external view returns (uint256) {
        return rentalHistory[user].length;
    }

    function getCountries(address user) external view returns (string[] memory) {
        return reputation[user].countries;
    }

    /**
     * @notice Convenience view returning key stats for dashboards including multi-token metrics.
     */
    function getUserSummary(address user)
        external
        view
        returns (
            uint256 creditScore,
            uint256 totalRentals,
            uint256 successRate,
            uint256 countriesCount,
            uint256 usdcVolume,
            uint256 eurcVolume,
            bool isMultiToken
        )
    {
        if (!hasToken[user]) {
            return (500, 0, 0, 0, 0, 0, false);
        }
        ReputationData memory rep = reputation[user];
        TokenMetrics memory metrics = tokenMetrics[user];

        uint256 _successRate = rep.totalRentals > 0
            ? (rep.successfulRentals * 100) / rep.totalRentals
            : 0;

        return (
            rep.creditScore,
            rep.totalRentals,
            _successRate,
            rep.countries.length,
            metrics.usdcVolume,
            metrics.eurcVolume,
            metrics.usdcRentals > 0 && metrics.eurcRentals > 0
        );
    }

    // ---------------------------------------
    // Soulbound Overrides (non-transferable)
    // ---------------------------------------

    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) but no transfers between users
        if (from != address(0) && to != address(0)) {
            revert("ReputationSBT: soulbound, transfer not allowed");
        }

        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public virtual override {
        revert("ReputationSBT: approvals disabled (soulbound)");
    }

    function setApprovalForAll(address, bool) public virtual override {
        revert("ReputationSBT: approvals disabled (soulbound)");
    }

    // ---------------------------------------
    // Admin / Role Management
    // ---------------------------------------

    function grantEscrowManager(address escrowContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(ESCROW_MANAGER_ROLE, escrowContract);
    }

    function revokeEscrowManager(address escrowContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _revokeRole(ESCROW_MANAGER_ROLE, escrowContract);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
