'use client'

import { useState, useEffect } from 'react'
import { User, Star, Eye } from 'lucide-react'
import PaymentForm from './PaymentForm'
import PaymentHistory from './PaymentHistory'
import FeedbackModal from './FeedbackModal'
import PropertiesModal from './PropertiesModal'
import PaymentEvidence from './PaymentEvidence'
import CCTPDemo from './CCTPDemo'
import { getProperties, type Property } from '../lib/properties'
import { getAllPayments, getPaymentStats, type PaymentRecord } from '../lib/paymentTracking'
import OnboardingModal from './OnboardingModal'

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
  const [showCCTPDemo, setShowCCTPDemo] = useState(false)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [properties, setProperties] = useState<Property[]>([])
  
  // Payment tracking state
  const [activeTenants, setActiveTenants] = useState(0)
  const [paymentStats, setPaymentStats] = useState({
    totalPayments: 0,
    totalAmount: 0,
    uniqueTenants: 0,
    uniqueProperties: 0
  })
  
  // Dynamic scores that update with payments
  const [reputationScore, setReputationScore] = useState(() => {
    // Check if we're in browser environment
    if (typeof window !== 'undefined') {
      // Try to load from localStorage first
      const saved = localStorage.getItem('crossrent-reputation-scores')
      if (saved) {
        try {
          return JSON.parse(saved)
        } catch (e) {
          console.log('Failed to parse saved reputation scores')
        }
      }
    }
    // Default values
    return {
      tenant: 750,
      landlord: 880
    }
  })
  const [totalPaid, setTotalPaid] = useState(0)
  const [paymentCount, setPaymentCount] = useState(0)

  // Function to update payment statistics
  const updatePaymentStats = () => {
    const allPayments = getAllPayments()
    const stats = getPaymentStats()
    
    setPaymentStats(stats)
    setActiveTenants(stats.uniqueTenants)
    
    console.log('📊 Payment stats updated:', {
      totalPayments: stats.totalPayments,
      uniqueTenants: stats.uniqueTenants,
      totalAmount: stats.totalAmount
    })
  }

  // Handle successful payment to update scores
  const handlePaymentSuccess = (amount: number) => {
    console.log('🎯 Payment success callback triggered:', { amount, userType })
    
    setTotalPaid(prev => {
      const newTotal = prev + amount
      console.log('💰 Total paid updated:', { prev, amount, newTotal })
      return newTotal
    })
    
    setPaymentCount(prev => {
      const newCount = prev + 1
      console.log('📊 Payment count updated:', { prev, newCount })
      return newCount
    })
    
    // Increase reputation score based on payment (enhanced for demo)
    const scoreIncrease = Math.min(50, Math.floor(amount / 100 * 5)) // Up to +50 points for demo
    console.log('🎯 DEMO: Reputation score calculation:', { amount, scoreIncrease })
    
    setReputationScore(prev => {
      const newScore = Math.min(1000, prev[userType] + scoreIncrease)
      const newState = {
        ...prev,
        [userType]: newScore
      }
      console.log('⭐ REPUTATION SCORE UPDATED - DEMO:', { 
        userType, 
        prevScore: prev[userType], 
        scoreIncrease, 
        newScore: newScore,
        change: `${prev[userType]} → ${newScore}`,
        fullState: newState
      })
      
      // Visual confirmation for demo
      setTimeout(() => {
        console.log('📈 VISIBLE CHANGE:', `Score changed from ${prev[userType]} to ${newScore}`)
      }, 100)
      
      // Persist to localStorage
      if (typeof window !== 'undefined') {
        localStorage.setItem('crossrent-reputation-scores', JSON.stringify(newState))
      }
      
      return newState
    })
    
    // Refresh properties list
    setProperties(getProperties())
    
    // Update payment statistics for landlord dashboard
    updatePaymentStats()
  }

  // Register the payment callback with parent component
  useEffect(() => {
    if (onRegisterPaymentCallback) {
      onRegisterPaymentCallback(handlePaymentSuccess)
    }
    
    // Load properties on mount
    setProperties(getProperties())
    
    // Load initial payment statistics
    updatePaymentStats()
  }, [onRegisterPaymentCallback, userType, setTotalPaid, setPaymentCount, setReputationScore])

  // Onboarding effect for first-time users
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const seen = localStorage.getItem('crossrent_onboarding_seen');
      if (!seen) {
        setShowOnboarding(true);
        localStorage.setItem('crossrent_onboarding_seen', 'true');
      }
    }
  }, []);

  return (
    <main className="px-4 py-8 md:px-8" id="dashboard">
      <div className="max-w-7xl mx-auto">
        {/* User Type Switcher */}
        <div className="mb-8 flex justify-center">
          <div className="bg-white rounded-2xl p-2 border border-gray-200 shadow-lg">
            <div className="flex space-x-2">
              <button
                onClick={() => setUserType('tenant')}
                className={`px-6 py-3 rounded-xl font-medium transition-all duration-300 flex items-center space-x-2 ${
                  userType === 'tenant'
                    ? 'bg-gradient-to-r from-blue-500 to-indigo-600 text-white shadow-lg'
                    : 'text-gray-600 hover:text-gray-800 hover:bg-gray-50'
                }`}
              >
                <User size={18} />
                <span>Tenant</span>
              </button>
              <button
                onClick={() => setUserType('landlord')}
                className={`px-6 py-3 rounded-xl font-medium transition-all duration-300 flex items-center space-x-2 ${
                  userType === 'landlord'
                    ? 'bg-gradient-to-r from-blue-500 to-indigo-600 text-white shadow-lg'
                    : 'text-gray-600 hover:text-gray-800 hover:bg-gray-50'
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
          <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6 md:p-8">
            {/* Progress Steps for Tenants */}
            {userType === 'tenant' && (
              <div className="mb-6 p-4 bg-gradient-to-r from-blue-500/20 to-gray-600/20 border border-blue-400/30 rounded-xl">
                <h3 className="text-lg font-semibold text-blue-200 mb-3">💳 Simple Payment Process</h3>
                <div className="flex items-center space-x-4 text-sm">
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-blue-500 rounded-full flex items-center justify-center text-white font-bold text-xs">1</div>
                    <span className="text-blue-200">Enter Details</span>
                  </div>
                  <div className="flex-1 h-px bg-blue-400/30"></div>
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-gray-400 rounded-full flex items-center justify-center text-white font-bold text-xs">2</div>
                    <span className="text-gray-300">Pay with USDC</span>
                  </div>
                  <div className="flex-1 h-px bg-gray-400/30"></div>
                  <div className="flex items-center space-x-2">
                    <div className="w-6 h-6 bg-gray-400 rounded-full flex items-center justify-center text-white font-bold text-xs">3</div>
                    <span className="text-gray-300">Build Credit</span>
                  </div>
                </div>
                <p className="text-xs text-blue-200/80 mt-3 italic">
                  💡 Payment wallet created automatically - no crypto experience needed!
                </p>
              </div>
            )}
            
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-bold text-white">
                {userType === 'tenant' ? 'Pay Rent' : 'Rent Management'}
              </h2>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() => setShowCCTPDemo(true)}
                  className="bg-gradient-to-r from-purple-500/20 to-purple-600/20 border border-purple-400/30 text-purple-200 px-4 py-2 rounded-xl font-medium hover:bg-purple-500/30 transition-all duration-300 flex items-center space-x-2"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                  </svg>
                  <span>🌉 CCTP Demo</span>
                </button>
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
                  className="bg-gradient-to-r from-blue-50 to-gray-50 border border-gray-300 text-gray-700 px-4 py-2 rounded-xl font-medium hover:bg-gray-100 transition-all duration-300 flex items-center space-x-2"
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
          <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6 md:p-8">
            <h2 className="text-2xl font-bold text-white mb-6">
              {userType === 'tenant' ? 'Payment History' : 'Received Payments'}
            </h2>
            <PaymentHistory userType={userType} />
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid md:grid-cols-4 gap-6 mt-8">
          {/* Reputation Score */}
          <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6">
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-lg font-semibold text-white">Reputation Score</h3>
              <Star className="w-5 h-5 text-yellow-400 fill-current" />
            </div>
            <div className="text-3xl font-bold bg-gradient-to-r from-yellow-400 to-orange-500 bg-clip-text text-transparent transition-all duration-500 pulse-on-change" key={`${reputationScore[userType]}-${Date.now()}`}>
              {reputationScore[userType]}/1000
            </div>
            <div className="flex items-center mt-2">
              <div className="flex-1 bg-gray-200 rounded-full h-2 mr-3">
                <div 
                  className="bg-gradient-to-r from-yellow-400 to-orange-500 h-2 rounded-full transition-all duration-500"
                  style={{ width: `${(reputationScore[userType] / 1000) * 100}%` }}
                ></div>
              </div>
              <span className="text-sm text-gray-600">
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

          {/* Active Tenants (Landlord Only) */}
          {userType === 'landlord' && (
            <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6">
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-lg font-semibold text-white">Active Tenants</h3>
                <User className="w-5 h-5 text-green-400" />
              </div>
              <div className="text-3xl font-bold bg-gradient-to-r from-green-400 to-blue-500 bg-clip-text text-transparent transition-all duration-500">
                {activeTenants}
              </div>
              <p className="text-sm text-green-200 mt-1">
                Paying tenants
              </p>
              <div className="mt-3 text-xs text-green-400/80">
                ${paymentStats.totalAmount.toLocaleString()} total received
              </div>
            </div>
          )}
          
          {/* Vault Protection */}
          <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6">
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-lg font-semibold text-white">
                {userType === 'tenant' ? 'Safety Contribution' : 'Default Protection'}
              </h3>
              <div className="w-5 h-5 rounded-full bg-gradient-to-r from-blue-400 to-purple-500 flex items-center justify-center">
                <span className="text-xs font-bold text-white">%</span>
              </div>
            </div>
            <div className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
              10%
            </div>
            <p className="text-sm text-purple-200 mt-1">
              {userType === 'tenant' 
                ? 'Extra deposit to safety pool' 
                : 'Vault covers tenant defaults'}
            </p>
            <div className="mt-3 text-xs text-purple-300">
              Pool: ${(127500 + (totalPaid * 0.1)).toLocaleString()} USDC
              {totalPaid > 0 && (
                <div className="text-green-400/60 mt-1">
                  +${(totalPaid * 0.1).toFixed(2)} from your payments
                </div>
              )}
            </div>
          </div>
          
          {/* In Escrow */}
          <div className="bg-gradient-to-br from-slate-950/95 via-gray-900/95 to-slate-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl p-6">
            <h3 className="text-lg font-semibold text-white mb-2">In Escrow</h3>
            <div className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
              $5,000 USDC
            </div>
            <p className="text-sm text-gray-600 mt-1">Security deposit</p>
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

      {showCCTPDemo && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-6xl w-full max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center p-4 border-b">
              <h2 className="text-xl font-bold">Circle CCTP Demonstration</h2>
              <button
                onClick={() => setShowCCTPDemo(false)}
                className="text-gray-500 hover:text-gray-700 text-xl font-bold"
              >
                ×
              </button>
            </div>
            <CCTPDemo />
          </div>
        </div>
      )}

      <OnboardingModal isOpen={showOnboarding} onClose={() => setShowOnboarding(false)} />

      <PropertiesModal 
        isOpen={showProperties}
        onClose={() => setShowProperties(false)}
        properties={properties}
      />
    </main>
  )
}