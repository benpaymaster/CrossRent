'use client'

import { useState, useEffect } from 'react'

export default function MottoOverlay() {
  const [isVisible, setIsVisible] = useState(true)

  useEffect(() => {
    // Hide the overlay after 5 seconds or when user clicks anywhere
    const timer = setTimeout(() => {
      setIsVisible(false)
    }, 5000)

    const handleClick = () => {
      setIsVisible(false)
    }

    document.addEventListener('click', handleClick)

    return () => {
      clearTimeout(timer)
      document.removeEventListener('click', handleClick)
    }
  }, [])

  if (!isVisible) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
      <div 
        className="text-center animate-pulse cursor-pointer"
        onClick={() => setIsVisible(false)}
      >
        <div className="text-6xl md:text-8xl font-bold mb-6">
          <span className="bg-gradient-to-r from-purple-300 via-emerald-300 to-blue-300 bg-clip-text text-transparent animate-motto-glow">
            CrossRent
          </span>
        </div>
        <div className="text-3xl md:text-5xl font-bold mb-8">
          <span className="bg-gradient-to-r from-emerald-300 via-cyan-300 to-purple-300 bg-clip-text text-transparent animate-fade-motto">
            Global Rent • Universal Credit • Global Reputation
          </span>
        </div>
        <div className="text-lg md:text-xl text-white/80 italic mb-8">
          "Building trust through transparency, one payment at a time"
        </div>
        <div className="text-sm text-white/60">
          Click anywhere to continue or wait 5 seconds...
        </div>
      </div>
    </div>
  )
}