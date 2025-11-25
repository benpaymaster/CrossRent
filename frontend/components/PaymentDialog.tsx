'use client'

import { useState, useRef, useEffect } from 'react'
import { X, Wallet, CreditCard, CheckCircle, ArrowRight } from 'lucide-react'
import { createWallet, executeTransfer, getWalletBalance, getAllWallets, type Wallet as WalletType, type Transfer } from '../lib/wallet'
import { openBridgeWidget } from '../lib/bridgeService'
import { BridgeKit } from '@circle-fin/bridge-kit'

// Demo helper: reset wallet balance
function resetWalletBalance(wallet: WalletType | null) {
  if (!wallet) return
  if (typeof window !== 'undefined') {
    const stored = localStorage.getItem('crossrent_wallets')
    let wallets = []
    if (stored) {
      try { wallets = JSON.parse(stored) } catch (e) {}
    }
    const idx = wallets.findIndex((w: any) => w.id === wallet.id)
    if (idx !== -1) {
      wallets[idx].balance = '1000.00'
      localStorage.setItem('crossrent_wallets', JSON.stringify(wallets))
      window.dispatchEvent(new CustomEvent('walletsUpdated'))
    }
  }
}
import { createEscrow, releaseRentPayment, getReputationScore, updateReputationScore } from '../lib/contracts'
import { addProperty } from '../lib/properties'
import { trackPayment } from '../lib/paymentTracking'
import toast from 'react-hot-toast'

interface PaymentDialogProps {
  isOpen: boolean
  onClose: () => void
  onPaymentSuccess?: (amount: number) => void
}

export default function PaymentDialog({ isOpen, onClose, onPaymentSuccess }: PaymentDialogProps) {
  // Listen for escrow events (example: using ethers.js)
  useEffect(() => {
    if (typeof window === 'undefined') return;
    let provider, contract;
    async function setupListeners() {
      try {
        // Replace with your contract address and ABI
        const escrowAddress = process.env.NEXT_PUBLIC_MULTISIG_ESCROW_ADDRESS;
        const escrowAbi = [
          "event EscrowCreated(uint256 indexed escrowId, address[] signatories, uint256 quorum, uint256 amount)",
          "event DepositReleased(uint256 indexed escrowId)"
        ];
        // Use ethers.js provider (Metamask or default)
        const { ethers } = await import("ethers");
        provider = new ethers.providers.Web3Provider(window.ethereum);
        contract = new ethers.Contract(escrowAddress, escrowAbi, provider);
        contract.on("EscrowCreated", (escrowId, signatories, quorum, amount) => {
          toast.success(`Escrow Created! ID: ${escrowId}, Quorum: ${quorum}`);
        });
        contract.on("DepositReleased", (escrowId) => {
          toast.success(`Deposit Released for Escrow ID: ${escrowId}`);
        });
      } catch (err) {
        // Ignore if not configured
      }
    }
    setupListeners();
    return () => {
      if (contract) {
        contract.removeAllListeners();
      }
    };
  }, []);
  // Toggle for dev vs prod payment logic
  const isDev = !process.env.NEXT_PUBLIC_CIRCLE_API_KEY
  const [amount, setAmount] = useState('')
  const [token, setToken] = useState<'USDC' | 'EURC'>('USDC')
  const [duration, setDuration] = useState('3')
  const [propertyAddress, setPropertyAddress] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)
  const [currentWallet, setCurrentWallet] = useState<WalletType | null>(null)
  const [walletBalance, setWalletBalance] = useState('0')
  const [step, setStep] = useState<'wallet' | 'payment' | 'success'>('wallet')

  const propertyRef = useRef<HTMLInputElement | null>(null)
  const amountRef = useRef<HTMLInputElement | null>(null)
  // New state for chain selection
  const [sourceChain, setSourceChain] = useState('polygon')
  const [destinationChain, setDestinationChain] = useState('polygon')

  // Load wallet on mount
  useEffect(() => {
    if (isOpen) {
      const wallets = getAllWallets()
      if (wallets.length > 0) {
        setCurrentWallet(wallets[0])
        setStep('payment')
        loadBalance(wallets[0].id)
      } else {
        setStep('wallet')
      }
    }
  }, [isOpen])

  const loadBalance = async (walletId: string) => {
    const balance = await getWalletBalance(walletId)
    setWalletBalance(balance)
  }

  const handleCreateWallet = async () => {
    setIsProcessing(true)
    try {
      const wallet = await createWallet('MATIC-AMOY')
      if (wallet) {
        setCurrentWallet(wallet)
        setWalletBalance(wallet.balance || '0')
        setStep('payment')
      }
    } catch (error) {
      console.error('Failed to create wallet:', error)
      toast.error('Failed to create wallet')
    } finally {
      setIsProcessing(false)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!currentWallet) return

    setIsProcessing(true)
    
    try {
      // 🏠 Step 1: Create escrow on smart contract
      const escrowResult = await createEscrow(
        '0x1234567890123456789012345678901234567890',
        amount,
        (parseFloat(amount) * 1.1).toFixed(2),
        propertyAddress,
        parseInt(duration)
      )
      if (!escrowResult.success) {
        throw new Error(escrowResult.error || 'Escrow creation failed')
      }
      toast.success('🏠 Escrow created successfully!')

      let transferResult
      if (isDev) {
        // Use mock wallet logic for dev/demo
        transferResult = await executeTransfer(currentWallet.id, {
          amount,
          destinationAddress: '0x1234567890123456789012345678901234567890',
          tokenId: token,
          sourceChain,
          destinationChain
        })
        if (!transferResult.success) {
          throw new Error(transferResult.error || 'Mock transfer failed')
        }
      } else {
        // Use Bridge Kit for real payments via openBridgeWidget
        try {
          transferResult = await openBridgeWidget({
            amount,
            sourceToken: token,
            destinationToken: token,
            sourceChain,
            destinationChain,
            destinationAddress: '0x1234567890123456789012345678901234567890',
          })
        } catch (err) {
          throw new Error('BridgeKit transfer failed: ' + (err?.message || err))
        }
        if (!(transferResult && (transferResult.status === 'complete' || transferResult.success))) {
          throw new Error(transferResult?.error || 'CCTP transfer failed')
        }
      }

      toast.success(`💰 ${token} payment sent!`)
      // Track payment
      const paymentRecord = trackPayment({
        amount: parseFloat(amount),
        propertyAddress,
        landlordAddress: '0x1234567890123456789012345678901234567890',
        tenantAddress: currentWallet.address,
        txHash: transferResult.transactionHash || transferResult.transactionId || 'tx_' + Date.now(),
        tenancyDuration: parseInt(duration)
      })
      addProperty({
        address: propertyAddress,
        amount,
        duration,
        tenantAddress: currentWallet.address
      })
      setStep('success')
      if (onPaymentSuccess) {
        onPaymentSuccess(parseFloat(amount))
      }
      await updateReputationScore(currentWallet.address, true)
      const rep = await getReputationScore(currentWallet.address)
      toast.success(`⭐ Reputation updated! New score: ${rep.score}`)
      console.log('Payment tracked:', paymentRecord)
      await loadBalance(currentWallet.id)
    } catch (error) {
      console.error('💥 Payment failed:', error)
      toast.error(`Payment failed: ${error instanceof Error ? error.message : 'Unknown error'}`)
    } finally {
      setIsProcessing(false)
    }
  }

  const handleClose = () => {
    setAmount('')
    setPropertyAddress('')
    setDuration('3')
    setStep('wallet')
    onClose()
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div 
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={handleClose}
      />
      
      {/* Dialog */}
      <div className="relative bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-white/10">
          <div>
            <h2 className="text-2xl font-bold text-white">💳 Make Rent Payment</h2>
            <p className="text-purple-300/80 text-sm font-medium italic mt-1 animate-pulse">
              Global Rent • Universal Credit • Global Reputation
            </p>
          </div>
          <button
            onClick={handleClose}
            className="text-white/60 hover:text-white transition-colors"
          >
            <X size={24} />
          </button>
        </div>

        {/* Progress Indicator */}
        <div className="p-6 border-b border-white/10">
          <div className="flex items-center justify-center space-x-4">
            <div className="flex items-center space-x-2">
              <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm ${
                step === 'wallet' ? 'bg-purple-500' : 'bg-green-500'
              }`}>
                {step === 'wallet' ? '1' : <CheckCircle size={16} />}
              </div>
              <span className={step === 'wallet' ? 'text-white font-medium' : 'text-green-400 font-medium'}>
                Create Wallet
              </span>
            </div>
            <div className={`flex-1 h-px ${step !== 'wallet' ? 'bg-green-400' : 'bg-gray-600'}`}></div>
            <div className="flex items-center space-x-2">
              <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm ${
                step === 'payment' ? 'bg-purple-500' : step === 'success' ? 'bg-green-500' : 'bg-gray-600'
              }`}>
                {step === 'success' ? <CheckCircle size={16} /> : '2'}
              </div>
              <span className={`${
                step === 'payment' ? 'text-white font-medium' : 
                step === 'success' ? 'text-green-400 font-medium' : 'text-gray-400'
              }`}>
                Set Payment
              </span>
            </div>
            <div className={`flex-1 h-px ${step === 'success' ? 'bg-green-400' : 'bg-gray-600'}`}></div>
            <div className="flex items-center space-x-2">
              <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm ${
                step === 'success' ? 'bg-green-500' : 'bg-gray-600'
              }`}>
                {step === 'success' ? <CheckCircle size={16} /> : '3'}
              </div>
              <span className={step === 'success' ? 'text-green-400 font-medium' : 'text-gray-400'}>
                Complete
              </span>
            </div>
          </div>
        </div>

        {/* Content */}
        <div className="p-6">
          {step === 'wallet' && (
            <div className="text-center">
              <div className="w-24 h-24 bg-gradient-to-r from-purple-500 to-blue-600 rounded-full flex items-center justify-center text-white text-3xl font-bold mx-auto mb-6 animate-pulse">
                🏦
              </div>
              <h3 className="text-3xl font-bold text-white mb-4">Step 1: Set Up Your Digital Payment Account</h3>
              <p className="text-purple-100 mb-6 text-xl leading-relaxed">
                We'll create a secure digital account for you to pay rent with USDC (digital dollars). It takes just seconds!
              </p>
              
              <div className="bg-gradient-to-r from-blue-500/20 to-purple-500/20 border border-blue-400/30 rounded-2xl p-4 mb-6">
                <div className="flex items-center space-x-3">
                  <div className="text-2xl">💡</div>
                  <div className="text-left">
                    <h4 className="font-semibold text-blue-200 mb-1">Why a digital account?</h4>
                    <p className="text-blue-100/80 text-sm">
                      Digital accounts let you securely store and send USDC (digital dollars) for rent payments. It's like having an instant, global bank account!
                    </p>
                  </div>
                </div>
              </div>

              <div className="bg-blue-500/10 rounded-xl p-4 mb-6">
                <div className="text-sm text-blue-200 space-y-2">
                  <div className="flex items-center justify-center space-x-2">
                    <span className="text-green-400">✓</span>
                    <span>Circle Programmable Wallet</span>
                  </div>
                  <div className="flex items-center justify-center space-x-2">
                    <span className="text-green-400">✓</span>
                    <span>1000 USDC starting balance</span>
                  </div>
                  <div className="flex items-center justify-center space-x-2">
                    <span className="text-green-400">✓</span>
                    <span>Ready for rent payments</span>
                  </div>
                </div>
              </div>
              
              <button
                onClick={handleCreateWallet}
                disabled={isProcessing}
                className="bg-gradient-to-r from-purple-500 to-blue-600 text-white px-10 py-4 rounded-xl font-bold text-lg hover:shadow-lg hover:shadow-purple-500/25 transition-all duration-300 disabled:opacity-50 flex items-center space-x-3 mx-auto"
              >
                {isProcessing ? (
                  <>
                    <div className="w-6 h-6 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span>Creating Your Account...</span>
                  </>
                ) : (
                  <>
                    <Wallet size={24} />
                    <span>🏦 Create My Digital Account</span>
                  </>
                )}
              </button>
            </div>
          )}

          {step === 'payment' && (
            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Property Address */}
              <div>
                <label className="block text-white/90 font-medium mb-3">Property Address</label>
                <input
                  ref={propertyRef}
                  type="text"
                  value={propertyAddress}
                  onChange={(e) => setPropertyAddress(e.target.value)}
                  placeholder="Enter property address"
                  className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-3 text-white placeholder-white/50 focus:border-purple-400 focus:outline-none transition-colors backdrop-blur-sm"
                  required
                />
              </div>

              {/* Tenancy Duration */}
              <div>
                <label className="block text-white/90 font-medium mb-3">Tenancy Duration (Months)</label>
                <select
                  value={duration}
                  onChange={(e) => setDuration(e.target.value)}
                  className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-3 text-white focus:border-purple-400 focus:outline-none transition-colors backdrop-blur-sm"
                >
                  <option value="3" className="bg-purple-900">3 Months</option>
                  <option value="6" className="bg-purple-900">6 Months</option>
                  <option value="9" className="bg-purple-900">9 Months</option>
                  <option value="12" className="bg-purple-900">12 Months</option>
                </select>
              </div>

              {/* Select Payment Token */}
              <div>
                <label className="block text-white/90 font-medium mb-2">Select Payment Token</label>
                <select
                  value={token}
                  onChange={e => setToken(e.target.value as 'USDC' | 'EURC')}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-black text-white"
                >
                  <option value="USDC">USDC (USD Coin)</option>
                  <option value="EURC">EURC (Euro Coin)</option>
                </select>
              </div>

              {/* Rent Amount */}
              <div>
                <label className="block text-white/90 font-medium mb-3">Rent Amount ({token})
                  <span className="ml-2 text-xs text-yellow-300">[token: {token}]</span>
                </label>
                <div className="relative">
                  <input
                    ref={amountRef}
                    type="number"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.00"
                    className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-3 text-white placeholder-white/50 focus:border-purple-400 focus:outline-none transition-colors backdrop-blur-sm pr-20"
                    required
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2 bg-gradient-to-r from-purple-400 to-indigo-500 text-white text-sm px-3 py-1 rounded-lg font-medium">
                    {token}
                  </div>
                </div>
              </div>

              {/* Source Chain Selection */}
              <div>
                <label className="block text-white/90 font-medium mb-2">Source Chain</label>
                <select
                  value={sourceChain}
                  onChange={e => setSourceChain(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent bg-black text-white"
                >
                  <option value="polygon">Polygon</option>
                  <option value="ethereum">Ethereum</option>
                  <option value="avalanche">Avalanche</option>
                </select>
              </div>

              {/* Destination Chain Selection */}
              <div>
                <label className="block text-white/90 font-medium mb-2">Destination Chain</label>
                <select
                  value={destinationChain}
                  onChange={e => setDestinationChain(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent bg-black text-white"
                >
                  <option value="polygon">Polygon</option>
                  <option value="ethereum">Ethereum</option>
                  <option value="avalanche">Avalanche</option>
                </select>
              </div>

              {/* Escrow Protection Info */}
              <div className="bg-gradient-to-r from-purple-500/20 to-indigo-600/20 border border-purple-400/30 rounded-xl p-4">
                <p className="text-purple-200 text-sm">
                  💡 Your payment will be held in escrow and released to the landlord according to the tenancy terms.
                  A 10% safety contribution will be added to protect both parties.
                </p>
              </div>

              {/* Pay Button */}
              <button
                type="submit"
                disabled={isProcessing || !amount || !propertyAddress}
                className="w-full bg-gradient-to-r from-purple-500 to-indigo-600 text-white py-4 rounded-xl font-semibold hover:shadow-lg hover:shadow-purple-500/25 transition-all duration-300 disabled:opacity-50 flex items-center justify-center space-x-2"
              >
                {isProcessing ? (
                  <>
                    <div className="w-6 h-6 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span>Processing Payment...</span>
                  </>
                ) : (
                  <>
                    <CreditCard size={20} />
                    <span>Pay ${amount || '0'} {token}</span>
                  </>
                )}
              </button>
            </form>
          )}

          {step === 'success' && (
            <div className="text-center">
              {/* Large Green Success Checkmark */}
              <div className="relative mb-6">
                <div className="w-32 h-32 bg-gradient-to-r from-green-500 to-emerald-600 rounded-full flex items-center justify-center mx-auto animate-bounce">
                  <CheckCircle className="w-20 h-20 text-white" />
                </div>
                <div className="absolute -bottom-2 left-1/2 transform -translate-x-1/2 bg-green-500 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg">
                  ✅ DEPOSIT RECEIVED
                </div>
              </div>
              
              <h3 className="text-3xl font-bold text-white mb-3">Payment Successful! 🎉</h3>
              <p className="text-white/70 mb-4 text-lg">
                Your rent payment of {amount} {token} has been processed successfully
              </p>
              
              {/* Enhanced Success Message */}
              <div className="bg-gradient-to-r from-green-500/20 to-emerald-600/20 border border-green-400/30 rounded-xl p-6 mb-6">
                <div className="flex items-center justify-center mb-4">
                  <div className="text-4xl mr-3">🏠</div>
                  <div>
                    <p className="text-green-300 font-bold text-xl">Deposit Received</p>
                    <p className="text-green-200/80 text-sm">Landlord has been notified</p>
                  </div>
                </div>
                
                <div className="text-sm text-green-200 space-y-3">
                  <div className="flex justify-between">
                    <span>Amount:</span>
                    <span className="font-semibold">{amount} {token}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Property:</span>
                    <span className="font-semibold">{propertyAddress}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Duration:</span>
                    <span className="font-semibold">{duration} months</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Safety Contribution:</span>
                    <span className="font-semibold">{(parseFloat(amount || '0') * 0.1).toFixed(2)} {token}</span>
                  </div>
                </div>
              </div>
              
              {/* Success Motto */}
              <div className="mb-6 animate-motto-glow">
                <p className="text-green-300 font-bold text-lg">
                  Global Rent ✓ Universal Credit ✓ Global Reputation ✓
                </p>
                <p className="text-green-200/80 text-sm italic mt-1">
                  You're building your global rental reputation!
                </p>
              </div>
              <div className="space-y-3">
                <button
                  onClick={() => setStep('payment')}
                  className="w-full bg-gradient-to-r from-purple-500 to-indigo-600 text-white px-6 py-3 rounded-xl font-semibold hover:shadow-lg hover:shadow-purple-500/25 transition-all duration-300 flex items-center justify-center space-x-2"
                >
                  <CreditCard size={20} />
                  <span>Make Another Payment</span>
                </button>
                <button
                  onClick={handleClose}
                  className="w-full bg-white/10 border border-white/20 text-white px-6 py-3 rounded-xl font-semibold hover:bg-white/20 transition-all duration-300"
                >
                  Close
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}