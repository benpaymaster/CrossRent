'use client'

import { useState, useRef, useEffect } from 'react'
import { X, Wallet, CreditCard, CheckCircle, ArrowRight } from 'lucide-react'
import { createWallet, executeTransfer, getWalletBalance, getAllWallets, type Wallet as WalletType, type Transfer } from '../lib/wallet'
import { createEscrow, releaseRentPayment, getReputationScore } from '../lib/contracts'
import { addProperty } from '../lib/properties'
import { trackPayment } from '../lib/paymentTracking'
import toast from 'react-hot-toast'

interface PaymentDialogProps {
  isOpen: boolean
  onClose: () => void
  onPaymentSuccess?: (amount: number) => void
}

export default function PaymentDialog({ isOpen, onClose, onPaymentSuccess }: PaymentDialogProps) {
  const [amount, setAmount] = useState('')
  const [duration, setDuration] = useState('3')
  const [propertyAddress, setPropertyAddress] = useState('')
  const [isProcessing, setIsProcessing] = useState(false)
  const [currentWallet, setCurrentWallet] = useState<WalletType | null>(null)
  const [walletBalance, setWalletBalance] = useState('0')
  const [step, setStep] = useState<'wallet' | 'payment' | 'success'>('wallet')

  const propertyRef = useRef<HTMLInputElement | null>(null)
  const amountRef = useRef<HTMLInputElement | null>(null)

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
        '0x1234567890123456789012345678901234567890', // Mock landlord
        amount,
        (parseFloat(amount) * 1.1).toFixed(2), // Include 10% safety contribution
        propertyAddress,
        parseInt(duration)
      )
      
      if (!escrowResult.success) {
        throw new Error(escrowResult.error || 'Escrow creation failed')
      }
      
      toast.success('🏠 Escrow created successfully!')
      
      // 💰 Step 2: Execute USDC transfer
      const transfer: Transfer = {
        amount,
        destinationAddress: '0x1234567890123456789012345678901234567890',
        tokenId: 'USDC',
        sourceChain: 'polygon',
        destinationChain: 'polygon'
      }

      const transferResult = await executeTransfer(currentWallet.id, transfer)
      
      if (transferResult.success) {
        toast.success('💰 USDC payment sent!')
        
        // 📊 Track the payment for evidence/monitoring
        const paymentRecord = trackPayment({
          amount: parseFloat(amount),
          propertyAddress,
          landlordAddress: '0x1234567890123456789012345678901234567890',
          tenantAddress: currentWallet.address,
          txHash: transferResult.transactionId || 'mock_tx_' + Date.now(),
          tenancyDuration: parseInt(duration)
        })
        
        // 🏠 Add property to landlord's view
        addProperty({
          address: propertyAddress,
          amount,
          duration,
          tenantAddress: currentWallet.address
        })
        
        setStep('success')
        
        // Call the callback to update dashboard scores
        if (onPaymentSuccess) {
          onPaymentSuccess(parseFloat(amount))
        }
        
        // ⭐ Step 3: Update reputation (on-time payment)
        await getReputationScore(currentWallet.address)
        toast.success('⭐ Reputation updated!')
        
        console.log('Payment tracked:', paymentRecord)
        
        // Refresh wallet balance
        await loadBalance(currentWallet.id)
      } else {
        throw new Error(transferResult.error || 'Transfer failed')
      }
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
              <div className="w-24 h-24 bg-gradient-to-r from-green-500 to-emerald-600 rounded-full flex items-center justify-center text-white text-3xl font-bold mx-auto mb-6 animate-pulse">
                🔗
              </div>
              <h3 className="text-3xl font-bold text-white mb-4">Step 1: Connect Your Crypto Wallet</h3>
              <p className="text-green-100 mb-6 text-xl leading-relaxed">
                You need a crypto wallet with USDC tokens to pay rent. Don't worry - we'll create one for you instantly!
              </p>
              
              <div className="bg-gradient-to-r from-yellow-500/20 to-orange-500/20 border border-yellow-400/30 rounded-2xl p-4 mb-6">
                <div className="flex items-center space-x-3">
                  <div className="text-2xl">💡</div>
                  <div className="text-left">
                    <h4 className="font-semibold text-yellow-200 mb-1">Why do I need a wallet?</h4>
                    <p className="text-yellow-100/80 text-sm">
                      Crypto wallets let you securely store and send USDC (digital dollars) for rent payments. It's like having a digital bank account!
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
                className="bg-gradient-to-r from-green-500 to-emerald-600 text-white px-10 py-4 rounded-xl font-bold text-lg hover:shadow-lg hover:shadow-green-500/25 transition-all duration-300 disabled:opacity-50 flex items-center space-x-3 mx-auto"
              >
                {isProcessing ? (
                  <>
                    <div className="w-6 h-6 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span>Creating Your Wallet...</span>
                  </>
                ) : (
                  <>
                    <Wallet size={24} />
                    <span>🚀 Create My Crypto Wallet</span>
                  </>
                )}
              </button>
            </div>
          )}

          {step === 'payment' && (
            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Wallet Info */}
              {currentWallet && (
                <div className="bg-gradient-to-r from-blue-500/20 to-purple-600/20 border border-blue-400/30 rounded-2xl p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center space-x-3">
                      <CreditCard className="w-6 h-6 text-blue-300" />
                      <h3 className="text-lg font-semibold text-blue-200">Your Wallet</h3>
                    </div>
                    <div className="text-right">
                      <p className="text-sm text-blue-100/80">Balance</p>
                      <p className="text-xl font-bold text-blue-200">{walletBalance} USDC</p>
                    </div>
                  </div>
                  <div className="text-sm text-blue-100/60">
                    <p className="mb-1">Address: {currentWallet.address.substring(0, 6)}...{currentWallet.address.substring(-4)}</p>
                    <p>Network: {currentWallet.blockchain}</p>
                  </div>
                </div>
              )}

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

              <div>
                <label className="block text-white/90 font-medium mb-3">Rent Amount (USDC)</label>
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
                    USDC
                  </div>
                </div>
              </div>

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

              <div className="bg-gradient-to-r from-purple-500/20 to-indigo-600/20 border border-purple-400/30 rounded-xl p-4">
                <p className="text-purple-200 text-sm">
                  💡 Your payment will be held in escrow and released to the landlord according to the tenancy terms.
                  A 10% safety contribution will be added to protect both parties.
                </p>
              </div>

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
                    <span>Pay ${amount || '0'} USDC</span>
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
                Your rent payment of {amount} USDC has been processed successfully
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
                    <span className="font-semibold">{amount} USDC</span>
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
                    <span className="font-semibold">{(parseFloat(amount || '0') * 0.1).toFixed(2)} USDC</span>
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