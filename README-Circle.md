# CrossRent - Circle Programmable Wallets Integration

This implementation uses **Circle Programmable Wallets** with **dev-controlled custody** for the Arc hackathon, as specified by the organizers.

## 🏗️ Architecture Overview

```
Frontend (HTML/JS) 
    ↓ HTTP API calls
Backend (Node.js)
    ↓ Circle SDK
Circle Programmable Wallets API
    ↓ Smart Contract Execution
Arc Blockchain (ARC-SEPOLIA testnet)
```

## 🔧 Circle Programmable Wallets Features

### Dev-Controlled Wallets
- **Custody Type**: `DEVELOPER` (dev-controlled, no user keys)
- **Account Type**: `SCA` (Smart Contract Account)
- **Supported Blockchains**: ETH-SEPOLIA, ARC-SEPOLIA
- **Native USDC**: Circle's native USDC token support

### CCTP Bridge Integration
- **Cross-Chain Transfer Protocol**: Native USDC bridging
- **Source Chains**: Ethereum Sepolia, Arbitrum Sepolia  
- **Destination**: Arc Sepolia testnet
- **Burn-and-Mint**: True cross-chain USDC (not wrapped)

### API Endpoints

#### Wallet Management
- `POST /api/wallet/create` - Create new programmable wallet
- `POST /api/wallet/fund` - Fund wallet with USDC
- `POST /api/transactions/status` - Get transaction status (polls every 5s)

#### USDC Operations  
- `POST /api/usdc/bridge` - Bridge USDC via Circle CCTP
- `POST /api/contract/execute` - Execute smart contract functions

## 🚀 Quick Start

### 1. Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your Circle API credentials
npm run dev
```

### 2. Frontend Usage
- Open `frontend/index.html` in browser
- Backend runs on `http://localhost:3001`
- Frontend automatically creates Circle wallets
- Demo includes CCTP bridge simulation

### 3. Circle Configuration
```env
CIRCLE_API_KEY=your_circle_api_key_here
CIRCLE_ENTITY_SECRET=your_circle_entity_secret_here
```

## 💡 Demo Flow

### Screen 1: CCTP Bridge
1. **Create tenant wallet** (Circle Programmable Wallet)
2. **Bridge USDC** from Ethereum to Arc via CCTP
3. **Real-time status** updates every 5 seconds

### Screen 2: Escrow Creation  
1. **Create escrow contract** on Arc blockchain
2. **Deposit USDC** into escrow (dev-controlled transaction)
3. **Smart contract execution** via Circle API

### Screen 3: Rental Management
1. **Pay monthly rent** (automated via Circle)
2. **Release deposits** (landlord-controlled via Circle)  
3. **Dispute resolution** (arbitrator-controlled via Circle)

## 🔐 Security Features

### Dev-Controlled Custody
- **No user private keys** - fully managed by developer
- **Secure API calls** - all transactions via Circle SDK
- **Audit trail** - complete transaction history
- **Multi-sig support** - enterprise-grade security

### Smart Contract Integration
- **ABI encoding** - proper contract function calls
- **Gas estimation** - optimized transaction fees  
- **Error handling** - robust fallback mechanisms
- **Event monitoring** - real-time contract events

## 📊 Status Monitoring

### Transaction Polling
```javascript
// Poll every 5 seconds for updates
setInterval(async () => {
    const status = await fetch('/api/transactions/status');
    updateUI(status);
}, 5000);
```

### Real-time Updates
- **Transaction confirmations**
- **Balance updates**  
- **Contract event notifications**
- **CCTP bridge status**

## 🎯 Arc Hackathon Compliance

✅ **Circle Programmable Wallets** - Dev-controlled custody mode  
✅ **CCTP Integration** - Native USDC cross-chain bridging  
✅ **Arc Testnet** - Full smart contract deployment  
✅ **Real-time Status** - 5-second polling for updates  
✅ **Demo Experience** - Complete 3-screen rental flow

## 🔗 API Documentation

### Create Wallet
```javascript
POST /api/wallet/create
{
    "userType": "tenant",
    "blockchains": ["ARC-SEPOLIA"],
    "accountType": "SCA", 
    "custodyType": "DEVELOPER"
}
```

### Bridge USDC
```javascript  
POST /api/usdc/bridge
{
    "walletId": "wallet-uuid",
    "sourceChain": "ETH-SEPOLIA",
    "destinationChain": "ARC-SEPOLIA", 
    "amount": "50.0",
    "token": "USDC"
}
```

### Execute Contract
```javascript
POST /api/contract/execute
{
    "walletId": "wallet-uuid",
    "contractAddress": "0x...",
    "method": "createEscrow",
    "args": {
        "monthlyRent": "1000",
        "deposit": "2000",
        "duration": "6"
    }
}
```

## 🏆 Winning Features

1. **Professional Integration** - Circle's enterprise-grade wallet infrastructure
2. **Native USDC Support** - True cross-chain USDC via CCTP (not bridged/wrapped)  
3. **Dev-Controlled UX** - Seamless user experience without wallet management
4. **Real-time Updates** - Live transaction monitoring and status updates
5. **Arc Testnet Ready** - Full deployment on Arc blockchain with USDC integration

This architecture demonstrates the **correct way to integrate UI with smart contracts using dev-controlled wallets** as required by Arc hackathon organizers.