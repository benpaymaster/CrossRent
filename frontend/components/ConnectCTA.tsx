"use client"

import { useEffect, useState } from 'react'
import { getAllWallets } from '../lib/wallet'

export default function ConnectCTA() {
  const [hasWallet, setHasWallet] = useState(true)

  useEffect(() => {
    const wallets = getAllWallets()
    setHasWallet(wallets.length > 0)

    const handler = () => {
      const w = getAllWallets()
      setHasWallet(w.length > 0)
    }

    window.addEventListener('walletsUpdated', handler)
    // openWalletCreation dispatched elsewhere will also update UI
    window.addEventListener('openWalletCreation', handler)

    return () => {
      window.removeEventListener('walletsUpdated', handler)
      window.removeEventListener('openWalletCreation', handler)
    }
  }, [])

  // Don't show if a wallet exists
  if (hasWallet) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-white/95 backdrop-blur-sm">
      <div className="text-center max-w-md mx-auto px-6">
        <button
          onClick={() => {
            // Scroll to dashboard and trigger creation flow
            document.getElementById('dashboard')?.scrollIntoView({ behavior: 'smooth' })
            window.dispatchEvent(new CustomEvent('openWalletCreation'))
          }}
          className="bg-blue-600 hover:bg-blue-700 text-white px-12 py-6 rounded-xl font-bold shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-200 text-lg mb-4 w-full"
        >
          <span className="text-2xl mr-3">🔗</span>
          Connect Wallet
        </button>
        <p className="text-sm text-gray-600 italic">
          Secure dev-controlled wallet created for you
        </p>
      </div>
    </div>
  )
}
