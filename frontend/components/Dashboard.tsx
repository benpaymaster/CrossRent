'use client'

import { useState, useEffect } from 'react'
import { User, Star, Eye } from 'lucide-react'
import PaymentForm from './PaymentForm'
import PaymentHistory from './PaymentHistory'
import FeedbackModal from './FeedbackModal'
import PropertiesModal from './PropertiesModal'
import PaymentEvidence from './PaymentEvidence'
import { getProperties, type Property } from '../lib/properties'

type UserType = 'tenant' | 'landlord'

interface DashboardProps {
  userType: UserType
  setUserType: (t: UserType) => void
  onRegisterPaymentCallback?: (callback: (amount: number) => void) => void
}

export default function Dashboard({ userType, setUserType, onRegisterPaymentCallback }: DashboardProps) {
  
  const [showFeedback, setShowFeedback] = useState(false)
  const [showProperties, setShowProperties] = useState(false)
  const [showEvidence, setShowEvidence] = useState(false)
  const [properties, setProperties] = useState<Property[]>([])
  
  // Dynamic scores that update with payments
  const [reputationScore, setReputationScore] = useState(() => ({
    tenant: 750,
    landlord: 880
  }))
  const [totalPaid, setTotalPaid] = useState(0)
  const [paymentCount, setPaymentCount] = useState(0)

  // Handle successful payment to update scores
  const handlePaymentSuccess = (amount: number) => {
    setTotalPaid(prev => prev + amount)
    setPaymentCount(prev => prev + 1)
    
    // Increase reputation score based on payment
    const scoreIncrease = Math.min(20, Math.floor(amount / 100 * 2)) // Up to +20 points
    setReputationScore(prev => ({
      ...prev,
      [userType]: Math.min(1000, prev[userType] + scoreIncrease)
    }))
    
    // Refresh properties list
    setProperties(getProperties())
  }

  // Register the payment callback with parent component
  useEffect(() => {
    if (onRegisterPaymentCallback) {
      onRegisterPaymentCallback(handlePaymentSuccess)
    }
    
    // Load properties on mount
    setProperties(getProperties())
  }, [onRegisterPaymentCallback, userType, setTotalPaid, setPaymentCount, setReputationScore])

  return (
    <main className="px-4 py-8 md:px-8" id="dashboard">
      <div className="max-w-7xl mx-auto">
        {/* User Type Switcher */}
        <div className="mb-8 flex justify-center">
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
                <span>Tenant</span>
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
                <span>Landlord</span>
              </button>
            </div>
          </div>
        </div>

        <div className="grid lg:grid-cols-2 gap-8">
          {/* Payment Form */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6 md:p-8">
            {/* Progress Steps for Tenants */}
            {userType === 'tenant' && (
              <div className="mb-6 p-4 bg-gradient-to-r from-purple-500/20 to-indigo-600/20 border border-purple-400/30 rounded-xl">
                <h3 className="text-lg font-semibold text-purple-200 mb-3">💳 Payment Process</h3>
                <div className="flex items-center space-x-4 text-sm">
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-purple-500 rounded-full flex items-center justify-center text-white font-bold text-xs">1</div>
                    <span className="text-purple-200">Create Wallet</span>
                  </div>
                  <div className="flex-1 h-px bg-purple-400/30"></div>
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-purple-400/50 rounded-full flex items-center justify-center text-white font-bold text-xs">2</div>
                    <span className="text-purple-200/70">Enter Amount</span>
                  </div>
                  <div className="flex-1 h-px bg-purple-400/30"></div>
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-purple-400/50 rounded-full flex items-center justify-center text-white font-bold text-xs">3</div>
                    <span className="text-purple-200/70">Pay Rent</span>
                  </div>
                </div>
              </div>
            )}
            
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-bold text-white">
                {userType === 'tenant' ? 'Pay Rent' : 'Rent Management'}
              </h2>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() => document.getElementById('guide')?.scrollIntoView({ behavior: 'smooth' })}
                  className="bg-gradient-to-r from-blue-500/20 to-blue-600/20 border border-blue-400/30 text-blue-200 px-4 py-2 rounded-xl font-medium hover:bg-blue-500/30 transition-all duration-300 flex items-center space-x-2"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <span>Test Guide</span>
                </button>
                <button
                  onClick={() => setShowEvidence(true)}
                  className="bg-gradient-to-r from-emerald-500/20 to-green-600/20 border border-emerald-400/30 text-emerald-200 px-4 py-2 rounded-xl font-medium hover:bg-emerald-500/30 transition-all duration-300 flex items-center space-x-2"
                >
                  <Eye size={16} />
                  <span>Evidence</span>
                </button>
                <button
                  onClick={() => setShowFeedback(true)}
                  className="bg-gradient-to-r from-purple-500/20 to-indigo-600/20 border border-purple-400/30 text-purple-200 px-4 py-2 rounded-xl font-medium hover:bg-purple-500/30 transition-all duration-300 flex items-center space-x-2"
                >
                  <Star size={16} />
                  <span>Feedback</span>
                </button>
              </div>
            </div>
            <PaymentForm 
              userType={userType} 
              onPaymentSuccess={handlePaymentSuccess}
              onShowProperties={() => setShowProperties(true)}
            />
          </div>

          {/* Payment History */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6 md:p-8">
            <h2 className="text-2xl font-bold text-white mb-6">
              {userType === 'tenant' ? 'Payment History' : 'Received Payments'}
            </h2>
            <PaymentHistory userType={userType} />
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid md:grid-cols-3 gap-6 mt-8">
          {/* Reputation Score */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6">
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-lg font-semibold text-white/90">Reputation Score</h3>
              <Star className="w-5 h-5 text-yellow-400 fill-current" />
            </div>
            <div className="text-3xl font-bold bg-gradient-to-r from-yellow-400 to-orange-500 bg-clip-text text-transparent">
              {reputationScore[userType]}/1000
            </div>
            <div className="flex items-center mt-2">
              <div className="flex-1 bg-white/20 rounded-full h-2 mr-3">
                <div 
                  className="bg-gradient-to-r from-yellow-400 to-orange-500 h-2 rounded-full transition-all duration-500"
                  style={{ width: `${(reputationScore[userType] / 1000) * 100}%` }}
                ></div>
              </div>
              <span className="text-sm text-white/60">
                {reputationScore[userType] >= 900 ? 'Outstanding' : 
                 reputationScore[userType] >= 800 ? 'Excellent' : 
                 reputationScore[userType] >= 700 ? 'Good' : 'Fair'}
              </span>
            </div>
            {paymentCount > 0 && (
              <div className="mt-3 text-xs text-green-400/80">
                +{Math.min(20, Math.floor(totalPaid / 100 * 2))} from {paymentCount} payment{paymentCount > 1 ? 's' : ''}
              </div>
            )}
          </div>
          
          {/* Vault Protection */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6">
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-lg font-semibold text-white/90">
                {userType === 'tenant' ? 'Safety Contribution' : 'Default Protection'}
              </h3>
              <div className="w-5 h-5 rounded-full bg-gradient-to-r from-blue-400 to-purple-500 flex items-center justify-center">
                <span className="text-xs font-bold text-white">%</span>
              </div>
            </div>
            <div className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
              10%
            </div>
            <p className="text-sm text-white/60 mt-1">
              {userType === 'tenant' 
                ? 'Extra deposit to safety pool' 
                : 'Vault covers tenant defaults'}
            </p>
            <div className="mt-3 text-xs text-white/50">
              Pool: ${(127500 + (totalPaid * 0.1)).toLocaleString()} USDC
              {totalPaid > 0 && (
                <div className="text-green-400/60 mt-1">
                  +${(totalPaid * 0.1).toFixed(2)} from your payments
                </div>
              )}
            </div>
          </div>
          
          {/* In Escrow */}
          <div className="backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20 shadow-2xl p-6">
            <h3 className="text-lg font-semibold text-white/90 mb-2">In Escrow</h3>
            <div className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
              $5,000 USDC
            </div>
            <p className="text-sm text-white/60 mt-1">Security deposit</p>
          </div>
        </div>
      </div>

      {showFeedback && (
        <FeedbackModal 
          isOpen={showFeedback} 
          onClose={() => setShowFeedback(false)} 
        />
      )}

      {showProperties && (
        <PropertiesModal 
          isOpen={showProperties} 
          onClose={() => setShowProperties(false)}
          properties={properties}
        />
      )}

      {showEvidence && (
        <PaymentEvidence 
          isOpen={showEvidence} 
          onClose={() => setShowEvidence(false)} 
        />
      )}

      <PropertiesModal 
        isOpen={showProperties}
        onClose={() => setShowProperties(false)}
        properties={properties}
      />
    </main>
  )
}