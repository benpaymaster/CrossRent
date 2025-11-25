# CrossRent: Technical Documentation

## Overview

CrossRent is a programmable rental escrow system built on Arc blockchain, integrating Circle Programmable Wallets and Bridge Kit to create the first truly cross-chain rental ecosystem.

## Architecture

### Smart Contracts (Solidity)

#### RentCreditEscrow.sol

**Purpose**: Core escrow contract managing rental agreements with programmable logic

```solidity
Key Functions:
- createEscrow(landlord, tenant, deposit, rent, duration)
- makeRentPayment(escrowId)
- releaseDeposit(escrowId)
- openDispute(escrowId, reason)
```

**Programmable Logic**:

- Automatic deposit release upon lease completion
- Conditional rent payments based on reputation scores
- Time-locked funds with dispute resolution mechanisms
- Multi-party consensus for dispute resolution (4/6 signatures)

#### ReputationSBT.sol

**Purpose**: Soul-bound token system for tenant credit scoring

```solidity
Key Features:
- Non-transferable reputation tokens
- Automatic score updates on payment
- Verifiable rental history
- Integration with escrow conditions
```

#### RiskBufferVault.sol

**Purpose**: Shared insurance pool protecting landlords

```solidity
Mechanics:
- 10% of each deposit flows to shared pool
- Algorithmic risk distribution
- Automated payout on defaults
- Community governance for threshold adjustments
```

#### OptimisticDemocracy.sol

**Purpose**: Programmable dispute resolution and consensus module

```solidity
Key Features:
- Raise disputes with metadata
- Multi-party voting on dispute outcomes
- Optimistic finalization with appeal options
- DAO integration for final decision-making
```

### Circle Integration

#### Programmable Wallets

```javascript
Implementation:
- Dev-controlled wallet creation
- Automatic funding for demo
- Cross-chain wallet management
- User-friendly onboarding
```

#### Bridge Kit (CCTP)

```javascript
Features:
- One-click USDC bridging from Ethereum to Arc
- Real-time status tracking
- Automatic network switching
- Error handling and fallbacks
```

## Frontend Architecture

### Technology Stack

- **HTML5/CSS3/JavaScript**: Core frontend
- **Tailwind CSS**: Responsive design system
- **Circle SDK**: Wallet and bridge integration
- **Web3.js**: Blockchain interaction

### Key Components

1. **Dual Perspective UI**: Switch between tenant/landlord views
2. **Real-time Notifications**: Live payment and dispute updates
3. **Interactive Escrow Management**: Create, fund, and manage agreements
4. **Cross-chain Bridge Interface**: Seamless USDC transfers
5. **Persistent Testing Guide**: Non-obstructive user guidance

## Backend API

### Technology Stack

- **Node.js/Express**: RESTful API server
- **In-memory Storage**: Demo data management
- **CORS Integration**: Frontend connectivity

### Endpoints

```
POST /api/wallet/create     - Create Circle wallet
POST /api/wallet/fund       - Fund user wallet
POST /api/usdc/bridge       - Bridge USDC via CCTP
POST /api/feedback          - Submit user feedback
GET  /api/feedback/stats    - Get usage statistics
GET  /api/health            - Health check
```

## Security Features

### Smart Contract Security

- **OpenZeppelin Standards**: Proven security patterns
- **Multi-signature Requirements**: 4/6 consensus for disputes
- **Time Locks**: Prevent premature fund access
- **Overflow Protection**: SafeMath implementation

### API Security

- **Input Validation**: All user inputs sanitized
- **Rate Limiting**: Prevent spam and abuse
- **Error Handling**: Graceful failure modes
- **CORS Configuration**: Secure cross-origin requests

## Deployment

### Arc Blockchain Deployment

```bash
# Deploy contracts to Arc testnet
forge script script/Deploy.s.sol --rpc-url $ARC_RPC --broadcast

# Verify contracts
forge verify-contract --chain arc $CONTRACT_ADDRESS
```

### Local Development

```bash
# Backend
cd backend && node server.js

# Frontend
cd frontend && python3 -m http.server 8081

# Access demo at http://localhost:8081
```

## Testing

### Smart Contract Tests

```solidity
// Test coverage includes:
- Escrow creation and funding
- Rent payment processing
- Deposit release mechanisms
- Dispute resolution workflows
- Reputation score updates
```

### Integration Tests

- Circle wallet creation flows
- USDC bridge operations
- Cross-chain transaction handling
- Error scenarios and recovery

### Consensus/Dispute Module Tests

```solidity
// Foundry tests in test/OptimisticDemocracy.t.sol validate:
// - Dispute raising and voting
// - Finalization and appeal logic
// - DAO voting and final decision
```

## Performance Metrics

### Transaction Costs (Arc Network)

- Escrow Creation: ~0.001 ETH
- Rent Payment: ~0.0005 ETH
- Deposit Release: ~0.0008 ETH
- Bridge Operation: Circle CCTP fees

### User Experience

- Wallet Creation: <30 seconds
- USDC Bridge: 2-5 minutes (CCTP standard)
- Rent Payment: <10 seconds
- Dispute Resolution: 24-48 hours

## Innovation Highlights

### Programmable Money Features

1. **Conditional Escrows**: Funds released only when lease conditions met
2. **Automated Credit Building**: Each payment builds verifiable reputation
3. **Risk Pooling**: Shared insurance through algorithmic fund distribution
4. **Cross-chain Rental**: Global rental agreements with local settlement

### User Experience Innovations

1. **Dual Perspective Demo**: Experience both tenant and landlord views
2. **One-click Onboarding**: Circle wallet creation with automatic funding
3. **Transparent Bridging**: Complex cross-chain operations made simple
4. **Real-time Feedback**: Live notifications and status updates

## Future Enhancements

### Phase 2 Features

- **Credit Score Integration**: Connect to traditional credit bureaus
- **Property Tokenization**: NFT-based property ownership
- **Yield Generation**: Deposit funds earn yield while in escrow
- **Global Expansion**: Support for multiple stablecoins (EURC, etc.)

### Scalability

- **Layer 2 Integration**: Reduce transaction costs
- **Cross-chain Expansion**: Support additional networks
- **Enterprise Features**: Bulk property management tools
- **Mobile App**: Native iOS/Android applications

## Contact & Support

**Repository**: https://github.com/benpaymaster/arc-rentcredit
**Live Demo**: http://localhost:8081
**Documentation**: README.md, USER_TESTING_GUIDE.md
**Presentation**: presentation.pdf

---

_Built for Arc Hackathon 2025 - Showcasing programmable money and cross-chain USDC_
