require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
// const { initiateDeveloperControlledWalletsClient } = require('@circle-fin/w3s-pw-web-sdk');

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Circle Programmable Wallets Client
let circleClient;

// Initialize Circle SDK
async function initializeCircle() {
    try {
        // For demo purposes, we'll simulate Circle SDK functionality
        // In production, uncomment below and install the correct Circle SDK:
        /*
        circleClient = initiateDeveloperControlledWalletsClient({
            apiKey: process.env.CIRCLE_API_KEY,
            entitySecret: process.env.CIRCLE_ENTITY_SECRET,
            baseUrl: 'https://api.circle.com'
        });
        */
        console.log('Circle Programmable Wallets client initialized (Demo Mode)');
    } catch (error) {
        console.error('Failed to initialize Circle client:', error);
        console.log('Running in demo mode without Circle SDK');
    }
}

// In-memory storage for demo (use database in production)
const wallets = new Map();
const transactions = new Map();

// Utility function to generate demo data
function generateDemoWalletData(userType) {
    const address = '0x' + require('crypto').randomBytes(20).toString('hex');
    const walletId = uuidv4();
    const userId = uuidv4();
    
    return {
        walletId,
        userId,
        address,
        userType,
        balance: userType === 'tenant' ? 0 : 100, // Landlords start with 100 USDC for demo
        createdAt: new Date()
    };
}

// API Endpoints

// Create Circle Programmable Wallet (dev-controlled)
app.post('/api/wallet/create', async (req, res) => {
    try {
        const { userType, blockchains, accountType, custodyType } = req.body;
        
        if (!userType) {
            return res.status(400).json({
                success: false,
                error: 'User type is required'
            });
        }

        let walletData;
        
        if (circleClient) {
            // Real Circle API call
            try {
                const response = await circleClient.createWallet({
                    idempotencyKey: uuidv4(),
                    accountType: accountType || 'SCA',
                    blockchains: blockchains || ['ETH-SEPOLIA', 'ARB-SEPOLIA'],
                    metadata: [
                        {
                            name: 'user_type',
                            value: userType
                        }
                    ]
                });

                walletData = {
                    walletId: response.data.walletId,
                    userId: uuidv4(),
                    address: response.data.accountsData[0].address,
                    userType,
                    balance: 0,
                    createdAt: new Date()
                };
                
                wallets.set(walletData.walletId, walletData);
                
            } catch (circleError) {
                console.error('Circle API error:', circleError);
                // Fallback to demo mode
                walletData = generateDemoWalletData(userType);
                wallets.set(walletData.walletId, walletData);
            }
        } else {
            // Demo mode
            walletData = generateDemoWalletData(userType);
            wallets.set(walletData.walletId, walletData);
        }

        console.log(`Created ${userType} wallet:`, walletData.address);

        res.json({
            success: true,
            walletId: walletData.walletId,
            userId: walletData.userId,
            address: walletData.address,
            userType: walletData.userType
        });

    } catch (error) {
        console.error('Wallet creation error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Fund wallet with USDC
app.post('/api/wallet/fund', async (req, res) => {
    try {
        const { walletId, amount, currency } = req.body;
        
        if (!walletId || !amount) {
            return res.status(400).json({
                success: false,
                error: 'Wallet ID and amount are required'
            });
        }

        const wallet = wallets.get(walletId);
        if (!wallet) {
            return res.status(404).json({
                success: false,
                error: 'Wallet not found'
            });
        }

        // For demo, just update the balance
        wallet.balance += parseFloat(amount);
        wallets.set(walletId, wallet);

        const txHash = '0xfund' + Date.now().toString(16);
        
        console.log(`Funded wallet ${wallet.address} with ${amount} ${currency}`);

        res.json({
            success: true,
            transactionHash: txHash,
            newBalance: wallet.balance
        });

    } catch (error) {
        console.error('Wallet funding error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Bridge USDC via Circle CCTP
app.post('/api/usdc/bridge', async (req, res) => {
    try {
        const { walletId, sourceChain, destinationChain, amount, token, destinationAddress } = req.body;
        
        if (!walletId || !amount) {
            return res.status(400).json({
                success: false,
                error: 'Wallet ID and amount are required'
            });
        }

        const wallet = wallets.get(walletId);
        if (!wallet) {
            return res.status(404).json({
                success: false,
                error: 'Wallet not found'
            });
        }

        // Simulate CCTP bridge transaction
        const txHash = '0xcctp' + Date.now().toString(16);
        const bridgeAmount = parseFloat(amount);
        
        // For demo, add the bridged amount to wallet balance
        wallet.balance += bridgeAmount;
        wallets.set(walletId, wallet);

        console.log(`CCTP bridge: ${bridgeAmount} USDC from ${sourceChain} to ${destinationChain}`);

        res.json({
            success: true,
            transactionHash: txHash,
            amount: bridgeAmount,
            sourceChain,
            destinationChain,
            status: 'PENDING'
        });

    } catch (error) {
        console.error('CCTP bridge error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Execute smart contract function
app.post('/api/contract/execute', async (req, res) => {
    try {
        const { walletId, contractAddress, method, args, blockchain } = req.body;
        
        if (!walletId || !contractAddress || !method) {
            return res.status(400).json({
                success: false,
                error: 'Wallet ID, contract address, and method are required'
            });
        }

        const wallet = wallets.get(walletId);
        if (!wallet) {
            return res.status(404).json({
                success: false,
                error: 'Wallet not found'
            });
        }

        // Simulate smart contract execution
        const txHash = '0xexec' + Date.now().toString(16);
        
        console.log(`Executing ${method} on contract ${contractAddress} for wallet ${wallet.address}`);
        console.log('Method args:', args);

        // Simulate different contract methods
        let result = {
            success: true,
            transactionHash: txHash,
            method,
            contractAddress,
            gasUsed: '21000'
        };

        switch (method) {
            case 'createEscrow':
                result.escrowId = Date.now();
                result.contractAddress = contractAddress;
                break;
            case 'payRent':
                const rentAmount = parseFloat(args.amount || 1000);
                if (wallet.balance >= rentAmount) {
                    wallet.balance -= rentAmount;
                    wallets.set(walletId, wallet);
                    result.amountPaid = rentAmount;
                } else {
                    return res.status(400).json({
                        success: false,
                        error: 'Insufficient wallet balance'
                    });
                }
                break;
            case 'releaseDeposit':
                const depositAmount = parseFloat(args.amount || 2000);
                wallet.balance += depositAmount;
                wallets.set(walletId, wallet);
                result.amountReleased = depositAmount;
                break;
            case 'createDispute':
                result.disputeId = Date.now();
                break;
        }

        res.json(result);

    } catch (error) {
        console.error('Contract execution error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Get transaction status
app.post('/api/transactions/status', async (req, res) => {
    try {
        const { walletId } = req.body;
        
        if (!walletId) {
            return res.status(400).json({
                success: false,
                error: 'Wallet ID is required'
            });
        }

        const wallet = wallets.get(walletId);
        if (!wallet) {
            return res.status(404).json({
                success: false,
                error: 'Wallet not found'
            });
        }

        // For demo, return some sample transaction statuses
        const sampleTransactions = [
            {
                transactionHash: '0xsample' + Date.now(),
                status: 'CONFIRMED',
                blockNumber: 12345,
                timestamp: new Date()
            }
        ];

        res.json({
            success: true,
            transactions: sampleTransactions,
            walletBalance: wallet.balance
        });

    } catch (error) {
        console.error('Transaction status error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date(),
        service: 'crossrent-circle-backend',
        circleEnabled: !!circleClient,
        walletsCount: wallets.size
    });
});

// In-memory storage for feedback (use database in production)
const feedbackData = {
    totalUsers: 0,
    feedbackEntries: [],
    ratings: [], // Start with no ratings
    featureVotes: {
        circle_wallets: 0,
        dual_perspective: 0,
        real_time_notifications: 0,
        escrow_management: 0,
        cross_chain_bridge: 0
    }
};

// Start with clean slate - no demo feedback
// feedbackData.feedbackEntries will be populated as real users submit feedback

// Feedback endpoints
app.post('/api/feedback', (req, res) => {
    try {
        const { rating, comment, features, timestamp } = req.body;
        
        // Validate rating
        if (!rating || rating < 1 || rating > 5) {
            return res.status(400).json({
                success: false,
                error: 'Rating must be between 1 and 5'
            });
        }
        
        // Add feedback entry
        const feedbackEntry = {
            id: uuidv4(),
            timestamp: timestamp || new Date().toISOString(),
            rating,
            comment: comment || '',
            features: features || []
        };
        
        feedbackData.feedbackEntries.push(feedbackEntry);
        feedbackData.ratings.push(rating);
        feedbackData.totalUsers += 1;
        
        // Update feature votes
        features.forEach(feature => {
            if (feedbackData.featureVotes[feature] !== undefined) {
                feedbackData.featureVotes[feature] += 1;
            }
        });
        
        console.log(`📝 New feedback received: ${rating}⭐ - ${comment}`);
        
        res.json({
            success: true,
            message: 'Feedback submitted successfully',
            feedbackId: feedbackEntry.id
        });
        
    } catch (error) {
        console.error('Error submitting feedback:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to submit feedback'
        });
    }
});

app.get('/api/feedback/stats', (req, res) => {
    try {
        const averageRating = feedbackData.ratings.length > 0 
            ? (feedbackData.ratings.reduce((a, b) => a + b, 0) / feedbackData.ratings.length).toFixed(1)
            : 0;
        
        const topFeatures = Object.entries(feedbackData.featureVotes)
            .sort(([,a], [,b]) => b - a)
            .slice(0, 3);
        
        const recentComments = feedbackData.feedbackEntries
            .slice(-3)
            .map(entry => entry.comment)
            .filter(comment => comment);
        
        res.json({
            success: true,
            stats: {
                totalUsers: feedbackData.totalUsers,
                averageRating: parseFloat(averageRating),
                totalFeedback: feedbackData.feedbackEntries.length,
                topFeatures,
                recentComments
            }
        });
        
    } catch (error) {
        console.error('Error getting feedback stats:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get feedback stats'
        });
    }
});

// Get all feedback (for admin/testing purposes)
app.get('/api/feedback', (req, res) => {
    try {
        const allFeedback = Array.from(feedbackStorage.values());
        
        // Sort by timestamp (newest first)
        allFeedback.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        
        res.json({
            success: true,
            feedback: allFeedback,
            total: allFeedback.length
        });
        
    } catch (error) {
        console.error('Error getting feedback:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get feedback'
        });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    console.error('Server error:', error);
    res.status(500).json({
        success: false,
        error: 'Internal server error'
    });
});

// Start server
async function startServer() {
    await initializeCircle();
    
    app.listen(PORT, () => {
        console.log(`🚀 CrossRent Circle Backend running on port ${PORT}`);
        console.log(`🔗 Circle Programmable Wallets: ${circleClient ? 'Connected' : 'Demo Mode'}`);
        console.log(`📋 Health check: http://localhost:${PORT}/api/health`);
    });
}

startServer().catch(console.error);