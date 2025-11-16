'use client'

import { useState } from 'react'
import { ChevronRight, User, ArrowRight } from 'lucide-react'
import PaymentDialog from './PaymentDialog'

interface GuideProps {
  userType: 'tenant' | 'landlord'
  setUserType: (t: 'tenant' | 'landlord') => void
  onPaymentSuccess?: (amount: number) => void
}

export default function Guide({ userType, setUserType, onPaymentSuccess }: GuideProps) {
  const [activeStep, setActiveStep] = useState(0)
  const [showPaymentDialog, setShowPaymentDialog] = useState(false)

  const handleStepClick = (index: number) => {
    setActiveStep(index)

    // Scroll to dashboard and trigger helpful actions for each step
    document.getElementById('dashboard')?.scrollIntoView({ behavior: 'smooth' })

    // Fire DOM events for PaymentForm to react to (focusing inputs)
    if (index === 0) {
      window.dispatchEvent(new CustomEvent('focusProperty'))
    } else if (index === 1) {
      window.dispatchEvent(new CustomEvent('focusAmount'))
    } else if (index === 2) {
      // Focus on pay button for payment step
      setTimeout(() => {
        const payButton = document.querySelector('button[type="submit"]') as HTMLButtonElement
        if (payButton) {
          payButton.focus()
          payButton.scrollIntoView({ behavior: 'smooth', block: 'center' })
        }
      }, 500)
    }

    // If user selected landlord step, switch view
    if (userType === 'landlord') {
      setUserType('landlord')
    }
  }

  const tenantSteps = [
    {
      title: '� Enter Property Details',
      description: 'Add your rental property address and tenancy terms',
      details: 'Input the exact property address and select your tenancy duration. This information will be stored securely on the blockchain.'
    },
    {
      title: '💰 Set Payment Amount',
      description: 'Specify monthly rent amount in USDC',
      details: 'Enter the exact rent amount as agreed in your tenancy. All payments are processed in USDC stablecoin for price stability.'
    },
    {
      title: '🏦 Pay Rent Instantly',
      description: 'Your payment is processed automatically with secure wallet creation',
      details: 'We create a secure wallet for you behind the scenes and process your USDC payment. Funds are held in smart contract escrow and released to landlord based on tenancy terms.'
    },
    {
      title: '⭐ Build Credit Score',
      description: 'Every payment improves your global rental reputation',
      details: 'On-time payments boost your reputation score, making it easier to rent anywhere in the world.'
    },
    {
      title: '� Track & Manage',
      description: 'Monitor payment history and upcoming due dates',
      details: 'View all transactions, payment confirmations, and manage your rental payments from one dashboard.'
    }
  ]

  const landlordSteps = [
    {
      title: '🏠 Add Properties',
      description: 'List your rental properties on the platform',
      details: 'Add property details, rental amounts, and tenancy terms. Each property gets a unique smart contract for secure escrow.'
    },
    {
      title: '👥 Invite Tenants',
      description: 'Send secure invitations to your tenants',
      details: 'Share property-specific payment links with tenants. They can start paying rent immediately with automatic wallet setup.'
    },
    {
      title: 'Monitor Payments',
      description: 'Track incoming rent payments in real-time',
      details: 'View payment confirmations, escrow status, and transaction history for all your properties in one dashboard.'
    },
    {
      title: 'Receive Funds',
      description: 'Automatic release from escrow to your wallet',
      details: 'Funds are automatically released from escrow to your wallet based on tenancy terms. No manual intervention needed.'
    }
  ]

  const steps = userType === 'tenant' ? tenantSteps : landlordSteps

  return (
    <section className="px-4 py-16 md:px-8" id="guide">
      <div className="max-w-7xl mx-auto">
        
        {/* HERO CTA - FIRST THING RENTERS SEE */}
        <div className="mb-16 text-center">
          <div className="backdrop-blur-xl bg-gradient-to-r from-purple-600/40 to-blue-600/40 rounded-3xl border-4 border-purple-400 shadow-2xl p-8 animate-pulse">
            <div className="mb-4">
              <div className="text-6xl mb-4">💳</div>
              <h1 className="text-5xl md:text-6xl font-black text-white mb-4">
                START PAYING RENT
              </h1>
              <p className="text-3xl text-purple-200 font-bold mb-6">
                ⚡ SIMPLE 3-STEP PROCESS ⚡
              </p>
            </div>
            
            <button 
              onClick={() => {
                setUserType('tenant')
                setShowPaymentDialog(true)
              }}
              className="bg-gradient-to-r from-purple-400 to-blue-400 text-white px-16 py-8 rounded-3xl font-black text-3xl hover:shadow-2xl hover:scale-110 transform transition-all duration-200 shadow-purple-400/50 animate-bounce border-4 border-white"
            >
              🚀 START PAYING RENT NOW 🚀
            </button>
            
            <p className="text-purple-200 mt-6 text-xl font-medium">
              👆 Click to begin - digital account created automatically for you
            </p>
          </div>
        </div>

        {/* Header */}
        <div className="text-center mb-12">
          <h2 className="text-4xl md:text-5xl font-bold bg-gradient-to-r from-white to-purple-200 bg-clip-text text-transparent mb-6">
            How CrossRent Works
          </h2>
          
          {/* Animated Motto */}
          <div className="mb-6">
            <p className="text-2xl md:text-3xl font-bold bg-gradient-to-r from-purple-300 via-blue-300 to-purple-300 bg-clip-text text-transparent animate-motto-glow">
              Global Rent. Universal Credit. Global Reputation.
            </p>
            <div className="mt-3 animate-fade-motto">
              <p className="text-lg text-purple-200/80 font-medium italic">
                "Building trust through transparency, one payment at a time"
              </p>
            </div>
          </div>
          
          <p className="text-xl text-white/70 max-w-3xl mx-auto leading-relaxed">
            Simple, secure, and transparent rent payments using Circle USDC on blockchain
          </p>
        </div>

        {/* User Type Selector */}
        <div className="flex justify-center mb-8">
          <div className="backdrop-blur-xl bg-white/10 rounded-2xl p-2 border border-white/20 shadow-2xl">
            <div className="flex space-x-2">
              <button
                onClick={() => setUserType('tenant')}
                className={`px-6 py-3 rounded-xl font-medium transition-all duration-300 flex items-center space-x-2 ${
                  userType === 'tenant'
                    ? 'bg-gradient-to-r from-purple-500 to-indigo-600 text-white shadow-lg'
                    : 'text-white/70 hover:text-white hover:bg-white/5'
                }`}
              >
                <User size={18} />
                <span>For Tenants</span>
              </button>
              <button
                onClick={() => setUserType('landlord')}
                className={`px-6 py-3 rounded-xl font-medium transition-all duration-300 flex items-center space-x-2 ${
                  userType === 'landlord'
                    ? 'bg-gradient-to-r from-purple-500 to-indigo-600 text-white shadow-lg'
                    : 'text-white/70 hover:text-white hover:bg-white/5'
                }`}
              >
                <User size={18} />
                <span>For Landlords</span>
              </button>
            </div>
          </div>
        </div>

        {/* Steps */}
        <div className="grid lg:grid-cols-2 gap-12">
          {/* Step List */}
          <div className="space-y-4">
            {steps.map((step, index) => (
              <div
                key={index}
                onClick={() => setActiveStep(index)}
                className={`p-6 rounded-2xl border cursor-pointer transition-all duration-300 ${
                  activeStep === index
                    ? 'backdrop-blur-xl bg-white/15 border-purple-400/50 shadow-lg'
                    : 'backdrop-blur-xl bg-white/5 border-white/10 hover:bg-white/10'
                }`}
              >
                <div className="flex items-center space-x-4">
                  <div className={`w-12 h-12 rounded-xl flex items-center justify-center font-bold text-lg ${
                    activeStep === index
                      ? 'bg-gradient-to-r from-purple-500 to-indigo-600 text-white'
                      : 'bg-white/10 text-white/60'
                  }`}>
                    {index + 1}
                  </div>
                  <div className="flex-1">
                    <h3 className="text-lg font-semibold text-white mb-1">{step.title}</h3>
                    <p className="text-white/60 text-sm">{step.description}</p>
                  </div>
                  <ChevronRight 
                    size={20} 
                    className={`transition-transform duration-300 ${
                      activeStep === index ? 'rotate-90 text-purple-400' : 'text-white/30'
                    }`}
                  />
                </div>
              </div>
            ))}
          </div>

          {/* Step Details */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-8">
            <div className="mb-6">
              <div className="w-16 h-16 bg-gradient-to-r from-purple-500 to-indigo-600 rounded-2xl flex items-center justify-center text-white text-2xl font-bold mb-4">
                {activeStep + 1}
              </div>
              <h3 className="text-2xl font-bold text-white mb-3">
                {steps[activeStep].title}
              </h3>
              <p className="text-white/80 leading-relaxed">
                {steps[activeStep].details}
              </p>
            </div>

            <div className="bg-gradient-to-r from-purple-500/20 to-indigo-600/20 border border-purple-400/30 rounded-2xl p-6 mb-6">
              <h4 className="font-semibold text-purple-200 mb-2">💡 Pro Tip</h4>
              <p className="text-purple-100/80 text-sm">
                {userType === 'tenant' 
                  ? 'Keep some extra USDC in your wallet to cover gas fees for transactions.'
                  : 'Set up automatic notifications to track when tenants make payments.'
                }
              </p>
            </div>

            <button 
              onClick={() => {
                setUserType('tenant')
                setShowPaymentDialog(true)
              }}
              className="w-full bg-gradient-to-r from-purple-500 to-blue-600 text-white py-4 rounded-2xl font-semibold hover:shadow-lg hover:shadow-purple-500/25 transition-all duration-300 flex items-center justify-center space-x-2"
            >
              <span>� Start Paying Rent Now</span>
              <ArrowRight size={20} />
            </button>
          </div>
        </div>

        {/* Features */}
        <div className="grid md:grid-cols-3 gap-8 mt-16">
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto bg-gradient-to-r from-green-500 to-emerald-600 rounded-2xl flex items-center justify-center text-white text-2xl font-bold mb-4">
              🛡️
            </div>
            <h3 className="text-xl font-semibold text-white mb-3">Escrow Protection</h3>
            <p className="text-white/70 text-sm leading-relaxed">
              Smart contract escrow ensures funds are secure until tenancy conditions are met
            </p>
          </div>

          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto bg-gradient-to-r from-blue-500 to-cyan-600 rounded-2xl flex items-center justify-center text-white text-2xl font-bold mb-4">
              ⚡
            </div>
            <h3 className="text-xl font-semibold text-white mb-3">Instant Payments</h3>
            <p className="text-white/70 text-sm leading-relaxed">
              USDC transactions process in seconds with minimal fees on blockchain
            </p>
          </div>

          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6 text-center">
            <div className="w-16 h-16 mx-auto bg-gradient-to-r from-purple-500 to-pink-600 rounded-2xl flex items-center justify-center text-white text-2xl font-bold mb-4">
              📊
            </div>
            <h3 className="text-xl font-semibold text-white mb-3">Full Transparency</h3>
            <p className="text-white/70 text-sm leading-relaxed">
              All transactions are recorded on blockchain for complete payment history
            </p>
          </div>
        </div>

        {/* Testing Guide Section */}
        <div className="mt-16 backdrop-blur-xl bg-gradient-to-r from-orange-500/10 to-red-600/10 rounded-3xl border border-orange-400/30 shadow-2xl p-8">
          <div className="text-center mb-8">
            <h3 className="text-3xl font-bold text-orange-200 mb-4">🧪 Test the Platform</h3>
            <p className="text-orange-100/80 text-lg">
              Try out all features in this demo environment
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
            <div className="bg-orange-500/20 border border-orange-400/30 rounded-xl p-4 text-center">
              <div className="text-2xl mb-2">👛</div>
              <h4 className="font-semibold text-orange-200 mb-2">Create Wallet</h4>
              <p className="text-xs text-orange-100/70">Test dev-controlled wallet creation with mock USDC balance</p>
            </div>
            
            <div className="bg-orange-500/20 border border-orange-400/30 rounded-xl p-4 text-center">
              <div className="text-2xl mb-2">💳</div>
              <h4 className="font-semibold text-orange-200 mb-2">Make Payment</h4>
              <p className="text-xs text-orange-100/70">Try the rent payment flow with simulated USDC transfers</p>
            </div>
            
            <div className="bg-orange-500/20 border border-orange-400/30 rounded-xl p-4 text-center">
              <div className="text-2xl mb-2">⭐</div>
              <h4 className="font-semibold text-orange-200 mb-2">Reputation System</h4>
              <p className="text-xs text-orange-100/70">See how your score builds with successful payments</p>
            </div>
            
            <div className="bg-orange-500/20 border border-orange-400/30 rounded-xl p-4 text-center">
              <div className="text-2xl mb-2">🛡️</div>
              <h4 className="font-semibold text-orange-200 mb-2">Vault Protection</h4>
              <p className="text-xs text-orange-100/70">10% safety buffer protects landlords from defaults</p>
            </div>
          </div>
          
          <div className="text-center">
            <button 
              onClick={() => {
                setUserType('tenant')
                setShowPaymentDialog(true)
              }}
              className="bg-gradient-to-r from-orange-500 to-red-600 text-white px-8 py-4 rounded-2xl font-bold text-lg hover:shadow-lg hover:shadow-orange-500/25 transition-all duration-300 inline-flex items-center space-x-2"
            >
              <span>🚀 Start Testing Now</span>
            </button>
          </div>
        </div>
      </div>

      <PaymentDialog 
        isOpen={showPaymentDialog}
        onClose={() => setShowPaymentDialog(false)}
        onPaymentSuccess={(amount) => {
          // Call the parent callback to update Dashboard scores
          if (onPaymentSuccess) {
            onPaymentSuccess(amount)
          }
          // Optionally close dialog after successful payment
          setShowPaymentDialog(false)
        }}
      />
    </section>
  )
}