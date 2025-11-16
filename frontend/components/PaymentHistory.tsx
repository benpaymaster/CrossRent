'use client'

import { useState, useEffect } from 'react'

interface PaymentHistoryProps {
  userType: 'tenant' | 'landlord'
}

interface Payment {
  id: string
  amount: number
  propertyAddress: string
  timestamp: string
  status: string
  txHash: string
  landlordAddress: string
  tenantAddress?: string
  tenancyDuration?: number
}

export default function PaymentHistory({ userType }: PaymentHistoryProps) {
  const [payments] = useState<Payment[]>([
    {
      id: '1',
      amount: 2500,
      propertyAddress: '123 Main St, Apt 4B',
      timestamp: '2025-11-01T00:00:00.000Z',
      status: 'completed',
      txHash: '0x1234...5678',
      landlordAddress: '0x742d35Cc6aF94ad2814bcdF161119B76655D4A05',
      tenantAddress: '0x8ba1f109ec94c6c2cA50Df56d19F2De12ee3C82b',
      tenancyDuration: 12
    },
    {
      id: '2',
      amount: 2500,
      propertyAddress: '123 Main St, Apt 4B',
      timestamp: '2025-10-01T00:00:00.000Z',
      status: 'completed',
      txHash: '0x2345...6789',
      landlordAddress: '0x742d35Cc6aF94ad2814bcdF161119B76655D4A05',
      tenantAddress: '0x8ba1f109ec94c6c2cA50Df56d19F2De12ee3C82b',
      tenancyDuration: 12
    },
    {
      id: '3',
      amount: 1875,
      propertyAddress: '456 Oak Ave, Unit 2A',
      timestamp: '2025-09-01T00:00:00.000Z',
      status: 'completed',
      txHash: '0x3456...7890',
      landlordAddress: '0x742d35Cc6aF94ad2814bcdF161119B76655D4A05',
      tenantAddress: '0x9cb2e220fc94c6c2cA50Df56d19F2De12ee3C82c',
      tenancyDuration: 6
    }
  ])

  const formatDate = (timestamp: string) => {
    return new Date(timestamp).toLocaleDateString()
  }

  const formatAmount = (amount: number) => {
    return `$${amount.toLocaleString()}`
  }

  return (
    <div className="backdrop-blur-xl bg-white/5 border border-white/20 rounded-2xl p-6">
      <h3 className="text-xl font-semibold text-white mb-6">
        {userType === 'tenant' ? 'Payment History' : 'Received Payments'}
      </h3>
      
      <div className="space-y-4">
        {payments.map((payment) => (
          <div key={payment.id} className="backdrop-blur-xl bg-white/5 border border-white/10 rounded-xl p-4">
            <div className="flex justify-between items-start mb-3">
              <div>
                <div className="text-white font-medium">{formatAmount(payment.amount)}</div>
                <div className="text-white/60 text-sm">{formatDate(payment.timestamp)}</div>
              </div>
              <span className="text-sm font-medium text-green-400">
                Completed
              </span>
            </div>
            
            <div className="text-white/70 text-sm mb-2">
              <strong>Property:</strong> {payment.propertyAddress}
            </div>
            
            {userType === 'landlord' && payment.tenantAddress && (
              <>
                <div className="text-white/70 text-sm mb-2">
                  <strong>Tenant:</strong> {payment.tenantAddress}
                </div>
                {payment.tenancyDuration && (
                  <div className="text-white/70 text-sm mb-2">
                    <strong>Duration:</strong> {payment.tenancyDuration} months
                  </div>
                )}
              </>
            )}
            
            {userType === 'tenant' && (
              <div className="text-white/70 text-sm mb-2">
                <strong>Landlord:</strong> {payment.landlordAddress}
              </div>
            )}
            
            <div className="text-white/50 text-xs">
              Transaction: {payment.txHash}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
