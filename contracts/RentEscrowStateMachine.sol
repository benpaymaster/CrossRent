// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

// Replace your current imports with these:
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract RentEscrow is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // Transaction ordering modes
    enum OrderingMode { FIFO, PGA, PBS, RANDOM }
    OrderingMode public orderingMode;

    // For PBS/Flashbots-style auction
    struct Bid {
        address sender;
        uint256 amount;
    }
    Bid[] public bids;
    mapping(address => uint256) public pendingBids;
    uint256 public auctionEndTime;
    bool public auctionActive;

    event OrderingModeChanged(OrderingMode newMode);
    event BidPlaced(address indexed sender, uint256 amount);
    event AuctionSettled(address winner, uint256 amount);
    // Roles
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    enum State { Initialized, DepositPaid, RentPaid, Completed, Refunded, Disputed }
    State public state;

    address public renter;
    address public landlord;

    uint256 public depositAmount;
    uint256 public rentAmount;

    uint256 public depositPaid;
    uint256 public rentPaid;

    DisputeResolutionDAO public dao;
    uint256 public disputeId;

    // Idempotency + safety flags
    bool public disputeActive;
    bool public disputeFinalized;

    // Events
    event DepositReceived(address indexed renter, uint256 amount);
    event RentReceived(address indexed renter, uint256 amount);
    event StateChanged(State newState);
    event RefundIssued(address indexed to, uint256 amount);
    event DisputeRaised(address indexed by, uint256 disputeId);
    event DisputeOutcomeApplied(uint256 disputeId, DisputeResolutionDAO.Outcome outcome);

    error NotRenter();
    error NotLandlord();
    error InvalidState();
    error IncorrectDeposit();
    error IncorrectRent();
    error DaoNotSet();
    error DisputeNotAllowed();
    error DisputeNotActive();
    error DisputeAlreadyFinalized();
    error PaymentFailed();
    error InvalidAddress();

    modifier onlyRenter() {
        if (msg.sender != renter) revert NotRenter();
        _;
    }
    modifier onlyLandlord() {
        if (msg.sender != landlord) revert NotLandlord();
        _;
    }
    modifier inState(State expected) {
        if (state != expected) revert InvalidState();
        _;
    }
    modifier canRaiseDispute() {
        // Only allow disputes when funds exist and before final payout
        if (!(state == State.DepositPaid || state == State.RentPaid)) revert DisputeNotAllowed();
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice initializer (replaces constructor for upgradeability)
    function initialize(
        address _renter,
        address _landlord,
        uint256 _depositAmount,
        uint256 _rentAmount,
        address _dao,
        address admin
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (_renter == address(0) || _landlord == address(0) || _dao == address(0) || admin == address(0)) {
            revert InvalidAddress();
        }

        renter = _renter;
        landlord = _landlord;
        depositAmount = _depositAmount;
        rentAmount = _rentAmount;

        dao = DisputeResolutionDAO(_dao);

        state = State.Initialized;

        orderingMode = OrderingMode.FIFO; // Default

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }
    // Admin can set ordering mode
    function setOrderingMode(OrderingMode mode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        orderingMode = mode;
        emit OrderingModeChanged(mode);
    }

    // --- PGA: Priority Gas Auction (simulate by allowing highest gas price tx to win) ---
    // In practice, this is handled by miners/validators, but we can simulate by allowing only the first tx per block or by gas price (not enforceable in EVM)

    // --- PBS/Flashbots-style: Auction for transaction inclusion ---
    function startAuction(uint256 durationSeconds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!auctionActive, "Auction already active");
        auctionActive = true;
        auctionEndTime = block.timestamp + durationSeconds;
        delete bids;
    }

    function placeBid() external payable {
        require(auctionActive, "Auction not active");
        require(block.timestamp < auctionEndTime, "Auction ended");
        require(msg.value > 0, "Bid must be positive");
        bids.push(Bid(msg.sender, msg.value));
        pendingBids[msg.sender] += msg.value;
        emit BidPlaced(msg.sender, msg.value);
    }

    function settleAuction() external {
        require(auctionActive, "Auction not active");
        require(block.timestamp >= auctionEndTime, "Auction not ended");
        auctionActive = false;
        // Find highest bid
        uint256 highest = 0;
        address winner;
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].amount > highest) {
                highest = bids[i].amount;
                winner = bids[i].sender;
            }
        }
        if (winner != address(0)) {
            // Winner can call privileged function (e.g., payDeposit/payRent) next
            // For demo: refund all others
            for (uint256 i = 0; i < bids.length; i++) {
                if (bids[i].sender != winner) {
                    payable(bids[i].sender).transfer(bids[i].amount);
                    pendingBids[bids[i].sender] = 0;
                }
            }
            emit AuctionSettled(winner, highest);
        }
    }

    // --- Randomized ordering (MEV resistance) ---
    function getRandomWinner() public view returns (address) {
        require(bids.length > 0, "No bids");
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, bids.length)));
        return bids[rand % bids.length].sender;
    }

    // Reject accidental ETH sends (keeps accounting clean)
    receive() external payable {
        revert("Direct ETH not accepted");
    }

    function payDeposit() external payable onlyRenter inState(State.Initialized) nonReentrant {
        // Transaction ordering logic
        if (orderingMode == OrderingMode.PBS) {
            require(!auctionActive, "Auction must be settled");
            // Only auction winner can call
            require(bids.length > 0, "No bids");
            address winner;
            uint256 highest = 0;
            for (uint256 i = 0; i < bids.length; i++) {
                if (bids[i].amount > highest) {
                    highest = bids[i].amount;
                    winner = bids[i].sender;
                }
            }
            require(msg.sender == winner, "Not auction winner");
        } else if (orderingMode == OrderingMode.RANDOM) {
            require(!auctionActive, "Auction must be settled");
            require(bids.length > 0, "No bids");
            require(msg.sender == getRandomWinner(), "Not selected");
        }
        if (msg.value != depositAmount) revert IncorrectDeposit();
        depositPaid = msg.value;
        state = State.DepositPaid;
        emit DepositReceived(msg.sender, msg.value);
        emit StateChanged(state);
    }

    function payRent() external payable onlyRenter inState(State.DepositPaid) nonReentrant {
        // Transaction ordering logic
        if (orderingMode == OrderingMode.PBS) {
            require(!auctionActive, "Auction must be settled");
            require(bids.length > 0, "No bids");
            address winner;
            uint256 highest = 0;
            for (uint256 i = 0; i < bids.length; i++) {
                if (bids[i].amount > highest) {
                    highest = bids[i].amount;
                    winner = bids[i].sender;
                }
            }
            require(msg.sender == winner, "Not auction winner");
        } else if (orderingMode == OrderingMode.RANDOM) {
            require(!auctionActive, "Auction must be settled");
            require(bids.length > 0, "No bids");
            require(msg.sender == getRandomWinner(), "Not selected");
        }
        if (msg.value != rentAmount) revert IncorrectRent();
        rentPaid = msg.value;
        state = State.RentPaid;
        emit RentReceived(msg.sender, msg.value);
        emit StateChanged(state);
    }

    function completeLease() external onlyLandlord inState(State.RentPaid) nonReentrant {
        // Optional policy: disallow completion while a dispute is active
        if (disputeActive) revert DisputeNotAllowed();

        state = State.Completed;
        emit StateChanged(state);

        _payout(landlord, depositPaid + rentPaid);
    }

    function refundDeposit() external onlyLandlord inState(State.DepositPaid) nonReentrant {
        // Optional policy: disallow refund while dispute is active
        if (disputeActive) revert DisputeNotAllowed();

        state = State.Refunded;
        emit StateChanged(state);
        emit RefundIssued(renter, depositPaid);

        _payout(renter, depositPaid);
    }

    function raiseDispute() external canRaiseDispute nonReentrant {
        if (msg.sender != renter && msg.sender != landlord) revert DisputeNotAllowed();
        if (address(dao) == address(0)) revert DaoNotSet();

        // Move to disputed state
        state = State.Disputed;
        emit StateChanged(state);

        disputeActive = true;
        disputeFinalized = false;

        // IMPORTANT:
        // DAO is configured to only accept disputes from approved escrows/factories.
        // You will grant ESCROW_ROLE to this escrow address (or to its factory) in the DAO.
        disputeId = dao.createDispute(address(this), renter, landlord, depositAmount);

        emit DisputeRaised(msg.sender, disputeId);
    }

    function applyDisputeOutcome() external nonReentrant {
        if (state != State.Disputed) revert InvalidState();
        if (!disputeActive) revert DisputeNotActive();
        if (disputeFinalized) revert DisputeAlreadyFinalized();
        if (disputeId == 0) revert DisputeNotActive();

        (DisputeResolutionDAO.Outcome outcome, bool resolved) = dao.getOutcome(disputeId);
        require(resolved && outcome != DisputeResolutionDAO.Outcome.None, "DAO not resolved");

        // Idempotency lock — guarantees this can only be applied once
        disputeFinalized = true;
        disputeActive = false;

        if (outcome == DisputeResolutionDAO.Outcome.FullRefund) {
            state = State.Refunded;
            emit StateChanged(state);
            emit RefundIssued(renter, depositPaid);
            _payout(renter, depositPaid);

        } else if (outcome == DisputeResolutionDAO.Outcome.PartialRefund) {
            // Demo policy: 50/50 split. In production, DAO should return exact bps/amounts.
            uint256 partialRefund = depositPaid / 2;

            state = State.Refunded;
            emit StateChanged(state);

            emit RefundIssued(renter, partialRefund);
            _payout(renter, partialRefund);

            // landlord receives remaining deposit + full rent
            _payout(landlord, (depositPaid - partialRefund) + rentPaid);

        } else {
            // NoRefund
            state = State.Completed;
            emit StateChanged(state);

            _payout(landlord, depositPaid + rentPaid);
        }

        emit DisputeOutcomeApplied(disputeId, outcome);
    }

    function _payout(address to, uint256 amount) internal {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert PaymentFailed();
    }

    uint256[45] private __gap;
}
