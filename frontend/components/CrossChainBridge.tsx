'use client';

import React, { useState, useEffect } from 'react';
import { openBridgeWidget, getAvailableChains, getAvailableTokens } from '../lib/bridgeService';

interface CrossChainBridgeProps {
    onBridgeComplete?: (result: any) => void;
    defaultAmount?: string;
    destinationAddress?: string;
}

export default function CrossChainBridge({ 
    onBridgeComplete, 
    defaultAmount, 
    destinationAddress 
}: CrossChainBridgeProps) {
    const [amount, setAmount] = useState(defaultAmount || '');
    const [sourceChain, setSourceChain] = useState('ETH-SEPOLIA');
    const [destinationChain, setDestinationChain] = useState('ARB-SEPOLIA');
    const [token, setToken] = useState('USDC');
    const [isLoading, setIsLoading] = useState(false);
    const [result, setResult] = useState<any>(null);

    const availableChains = getAvailableChains();
    const availableTokens = getAvailableTokens();

    const handleBridge = async () => {
        if (!amount || parseFloat(amount) <= 0) {
            alert('Please enter a valid amount');
            return;
        }

        setIsLoading(true);
        try {
            const bridgeResult = await openBridgeWidget({
                amount,
                sourceToken: token,
                destinationToken: token,
                sourceChain,
                destinationChain,
                destinationAddress
            });

            setResult(bridgeResult);
            if (onBridgeComplete) {
                onBridgeComplete(bridgeResult);
            }
        } catch (error) {
            console.error('Bridge failed:', error);
            alert('Bridge transfer failed. Please try again.');
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="bg-white rounded-lg border border-gray-200 p-6">
            <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                    <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                    </svg>
                </div>
                <div>
                    <h3 className="text-lg font-semibold text-gray-900">Cross-Chain Bridge</h3>
                    <p className="text-sm text-gray-600">Transfer USDC across blockchain networks</p>
                </div>
            </div>

            {!result ? (
                <div className="space-y-4">
                    {/* Token Selection */}
                    <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">
                            Token
                        </label>
                        <select
                            value={token}
                            onChange={(e) => setToken(e.target.value)}
                            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                        >
                            {availableTokens.map((t) => (
                                <option key={t.symbol} value={t.symbol}>
                                    {t.name} ({t.symbol})
                                </option>
                            ))}
                        </select>
                    </div>

                    {/* Amount Input */}
                    <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">
                            Amount
                        </label>
                        <input
                            type="number"
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            placeholder="Enter amount"
                            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                            min="0"
                            step="0.01"
                        />
                    </div>

                    {/* Chain Selection */}
                    <div className="grid grid-cols-2 gap-4">
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                From Chain
                            </label>
                            <select
                                value={sourceChain}
                                onChange={(e) => setSourceChain(e.target.value)}
                                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                            >
                                {availableChains.map((chain) => (
                                    <option key={chain.id} value={chain.id}>
                                        {chain.name}
                                    </option>
                                ))}
                            </select>
                        </div>

                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                To Chain
                            </label>
                            <select
                                value={destinationChain}
                                onChange={(e) => setDestinationChain(e.target.value)}
                                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                            >
                                {availableChains.map((chain) => (
                                    <option key={chain.id} value={chain.id}>
                                        {chain.name}
                                    </option>
                                ))}
                            </select>
                        </div>
                    </div>

                    {destinationAddress && (
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                Destination Address
                            </label>
                            <input
                                type="text"
                                value={destinationAddress}
                                readOnly
                                className="w-full px-3 py-2 bg-gray-50 border border-gray-300 rounded-lg text-gray-600 font-mono text-sm"
                            />
                        </div>
                    )}

                    {/* Bridge Button */}
                    <button
                        onClick={handleBridge}
                        disabled={isLoading || !amount}
                        className="w-full bg-blue-600 text-white py-3 px-4 rounded-lg font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                    >
                        {isLoading ? (
                            <>
                                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                                Initiating Bridge...
                            </>
                        ) : (
                            <>
                                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                                </svg>
                                Start Bridge Transfer
                            </>
                        )}
                    </button>

                    <div className="text-xs text-gray-500 bg-gray-50 p-3 rounded-lg">
                        <p className="font-medium mb-1">Cross-Chain Transfer powered by Circle CCTP</p>
                        <p>• Native USDC transfers across chains</p>
                        <p>• No wrapped tokens or liquidity pools</p>
                        <p>• Estimated completion: 10-15 minutes</p>
                    </div>
                </div>
            ) : (
                <div className="text-center py-6">
                    <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                        <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
                        </svg>
                    </div>
                    <h3 className="text-lg font-semibold text-gray-900 mb-2">Bridge Transfer Initiated</h3>
                    <p className="text-gray-600 mb-4">
                        Your cross-chain transfer has been started and will complete in 10-15 minutes.
                    </p>
                    
                    <div className="bg-gray-50 rounded-lg p-4 mb-4">
                        <div className="text-sm space-y-2">
                            <div className="flex justify-between">
                                <span className="text-gray-600">Transfer ID:</span>
                                <span className="font-mono text-xs">{result.transferId}</span>
                            </div>
                            <div className="flex justify-between">
                                <span className="text-gray-600">Amount:</span>
                                <span className="font-medium">{amount} {token}</span>
                            </div>
                            <div className="flex justify-between">
                                <span className="text-gray-600">Status:</span>
                                <span className="capitalize text-blue-600 font-medium">{result.status}</span>
                            </div>
                            {result.transactionHash && (
                                <div className="flex justify-between">
                                    <span className="text-gray-600">Tx Hash:</span>
                                    <span className="font-mono text-xs">{result.transactionHash.slice(0, 10)}...</span>
                                </div>
                            )}
                        </div>
                    </div>

                    <button
                        onClick={() => {
                            setResult(null);
                            setAmount('');
                        }}
                        className="text-blue-600 hover:text-blue-700 font-medium text-sm"
                    >
                        Start New Transfer
                    </button>
                </div>
            )}
        </div>
    );
}