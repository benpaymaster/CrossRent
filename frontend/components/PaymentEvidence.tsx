'use client'

import { useState, useEffect } from 'react'
import { 
  getAllPayments, 
  getPaymentStats, 
  generateEvidenceReport, 
  seedDemoPayments, 
  getPerformanceMetrics,
  type PaymentRecord 
} from '../lib/paymentTracking'

interface PaymentEvidenceProps {
  isOpen: boolean
  onClose: () => void
}

export default function PaymentEvidence({ isOpen, onClose }: PaymentEvidenceProps) {
  const [activeTab, setActiveTab] = useState<'overview' | 'payments' | 'evidence'>('overview')
  const [payments, setPayments] = useState<PaymentRecord[]>([])
  const [stats, setStats] = useState(getPaymentStats())
  const [evidenceReport, setEvidenceReport] = useState(generateEvidenceReport())

  useEffect(() => {
    if (isOpen) {
      // Seed demo data if no payments exist
      if (getAllPayments().length === 0) {
        seedDemoPayments()
      }
      
      refreshData()
    }
  }, [isOpen])

  const refreshData = () => {
    setPayments(getAllPayments())
    setStats(getPaymentStats())
    setEvidenceReport(generateEvidenceReport())
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div 
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      />
      
      {/* Modal */}
      <div className="relative bg-gradient-to-br from-purple-950/95 via-slate-900/95 to-purple-950/95 backdrop-blur-xl border border-white/20 rounded-3xl shadow-2xl max-w-6xl w-full max-h-[90vh] overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-white/10">
          <div>
            <h2 className="text-2xl font-bold text-white">📊 Payment Evidence & Monitoring</h2>
            <p className="text-purple-300/80 text-sm mt-1">Track, monitor and evaluate all rental payments</p>
          </div>
          <button
            onClick={onClose}
            className="text-white/60 hover:text-white transition-colors text-xl"
          >
            ✕
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-white/10">
          {[
            { key: 'overview', label: '📈 Overview', icon: '📈' },
            { key: 'payments', label: '💳 All Payments', icon: '💳' },
            { key: 'evidence', label: '📋 Evidence Report', icon: '📋' }
          ].map(tab => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key as any)}
              className={`px-6 py-4 font-medium transition-all duration-200 ${
                activeTab === tab.key
                  ? 'text-white border-b-2 border-purple-400 bg-white/5'
                  : 'text-white/70 hover:text-white hover:bg-white/5'
              }`}
            >
              <span className="mr-2">{tab.icon}</span>
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="p-6 overflow-y-auto max-h-[60vh]">
          
          {/* Overview Tab */}
          {activeTab === 'overview' && (
            <div className="space-y-6">
              {/* Key Metrics */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="bg-gradient-to-r from-emerald-500/20 to-green-500/20 border border-emerald-400/30 rounded-xl p-4">
                  <div className="text-2xl font-bold text-emerald-300">{stats.totalPayments}</div>
                  <div className="text-emerald-200/80 text-sm">Total Payments</div>
                </div>
                <div className="bg-gradient-to-r from-blue-500/20 to-cyan-500/20 border border-blue-400/30 rounded-xl p-4">
                  <div className="text-2xl font-bold text-blue-300">${stats.totalAmount.toLocaleString()}</div>
                  <div className="text-blue-200/80 text-sm">Total Volume</div>
                </div>
                <div className="bg-gradient-to-r from-purple-500/20 to-pink-500/20 border border-purple-400/30 rounded-xl p-4">
                  <div className="text-2xl font-bold text-purple-300">{stats.successRate}%</div>
                  <div className="text-purple-200/80 text-sm">Success Rate</div>
                </div>
                <div className="bg-gradient-to-r from-amber-500/20 to-orange-500/20 border border-amber-400/30 rounded-xl p-4">
                  <div className="text-2xl font-bold text-amber-300">{stats.uniqueProperties}</div>
                  <div className="text-amber-200/80 text-sm">Properties</div>
                </div>
              </div>

              {/* Recent Activity */}
              <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
                <h3 className="text-xl font-bold text-white mb-4">🕐 Recent Activity</h3>
                <div className="space-y-3">
                  {payments.slice(0, 5).map(payment => (
                    <div key={payment.id} className="flex items-center justify-between p-3 bg-white/5 rounded-xl">
                      <div className="flex items-center space-x-3">
                        <div className={`w-3 h-3 rounded-full ${
                          payment.status === 'confirmed' ? 'bg-green-500' : 
                          payment.status === 'pending' ? 'bg-yellow-500' : 'bg-red-500'
                        }`}></div>
                        <div>
                          <div className="text-white font-medium">${payment.amount} USDC</div>
                          <div className="text-white/60 text-sm">{payment.propertyAddress.substring(0, 30)}...</div>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-white/80 text-sm">{payment.status}</div>
                        <div className="text-white/60 text-xs">{new Date(payment.timestamp).toLocaleDateString()}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Payments Tab */}
          {activeTab === 'payments' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-xl font-bold text-white">All Payment Records</h3>
                <button 
                  onClick={refreshData}
                  className="bg-purple-500/20 border border-purple-400/30 text-purple-300 px-4 py-2 rounded-xl text-sm hover:bg-purple-500/30 transition-colors"
                >
                  🔄 Refresh
                </button>
              </div>
              
              <div className="space-y-3">
                {payments.map(payment => (
                  <div key={payment.id} className="bg-white/5 border border-white/10 rounded-xl p-4">
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center space-x-3">
                        <div className={`w-4 h-4 rounded-full ${
                          payment.status === 'confirmed' ? 'bg-green-500' : 
                          payment.status === 'pending' ? 'bg-yellow-500' : 'bg-red-500'
                        }`}></div>
                        <div className="text-white font-bold">${payment.amount} USDC</div>
                        <div className={`px-2 py-1 rounded-lg text-xs font-medium ${
                          payment.status === 'confirmed' ? 'bg-green-500/20 text-green-300' : 
                          payment.status === 'pending' ? 'bg-yellow-500/20 text-yellow-300' : 'bg-red-500/20 text-red-300'
                        }`}>
                          {payment.status}
                        </div>
                      </div>
                      <div className="text-white/60 text-sm">
                        {new Date(payment.timestamp).toLocaleString()}
                      </div>
                    </div>
                    
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-sm">
                      <div>
                        <div className="text-white/60">Property</div>
                        <div className="text-white">{payment.propertyAddress}</div>
                      </div>
                      <div>
                        <div className="text-white/60">Transaction</div>
                        <div className="text-purple-300 font-mono text-xs">{payment.txHash.substring(0, 20)}...</div>
                      </div>
                      <div>
                        <div className="text-white/60">Duration</div>
                        <div className="text-white">{payment.tenancyDuration} months</div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Evidence Report Tab */}
          {activeTab === 'evidence' && (
            <div className="space-y-6">
              <div className="bg-gradient-to-r from-emerald-500/20 to-cyan-500/20 border border-emerald-400/30 rounded-2xl p-6">
                <h3 className="text-xl font-bold text-white mb-4">📋 Evidence Summary</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-2xl font-bold text-emerald-300">{evidenceReport.summary.totalPayments}</div>
                    <div className="text-emerald-200/80 text-sm">Confirmed Payments</div>
                  </div>
                  <div>
                    <div className="text-2xl font-bold text-cyan-300">${evidenceReport.summary.totalAmount.toLocaleString()}</div>
                    <div className="text-cyan-200/80 text-sm">Total Volume</div>
                  </div>
                  <div>
                    <div className="text-2xl font-bold text-blue-300">{evidenceReport.summary.uniqueTenants}</div>
                    <div className="text-blue-200/80 text-sm">Unique Tenants</div>
                  </div>
                  <div>
                    <div className="text-2xl font-bold text-purple-300">{evidenceReport.summary.successRate}%</div>
                    <div className="text-purple-200/80 text-sm">Success Rate</div>
                  </div>
                </div>
              </div>

              {/* Monthly Breakdown */}
              <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
                <h3 className="text-xl font-bold text-white mb-4">📊 Monthly Breakdown</h3>
                <div className="space-y-3">
                  {evidenceReport.monthlyBreakdown.map((month, index) => (
                    <div key={index} className="flex items-center justify-between p-3 bg-white/5 rounded-xl">
                      <div className="text-white font-medium">{month.month}</div>
                      <div className="flex items-center space-x-4">
                        <div className="text-white/80">{month.count} payments</div>
                        <div className="text-green-300 font-bold">${month.amount.toLocaleString()}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Export Options */}
              <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
                <h3 className="text-xl font-bold text-white mb-4">📤 Export Evidence</h3>
                <div className="flex space-x-4">
                  <button 
                    onClick={() => {
                      const data = JSON.stringify(evidenceReport, null, 2)
                      const blob = new Blob([data], { type: 'application/json' })
                      const url = URL.createObjectURL(blob)
                      const a = document.createElement('a')
                      a.href = url
                      a.download = 'crossrent-evidence-report.json'
                      a.click()
                    }}
                    className="bg-blue-500/20 border border-blue-400/30 text-blue-300 px-4 py-2 rounded-xl hover:bg-blue-500/30 transition-colors"
                  >
                    📄 Download JSON Report
                  </button>
                  <button 
                    onClick={() => {
                      navigator.clipboard.writeText(JSON.stringify(evidenceReport, null, 2))
                      alert('Evidence report copied to clipboard!')
                    }}
                    className="bg-purple-500/20 border border-purple-400/30 text-purple-300 px-4 py-2 rounded-xl hover:bg-purple-500/30 transition-colors"
                  >
                    📋 Copy to Clipboard
                  </button>
                </div>
              </div>
            </div>
          )}

        </div>
      </div>
    </div>
  )
}