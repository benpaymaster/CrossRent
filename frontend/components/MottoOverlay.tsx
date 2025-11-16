'use client'

import { useState, useEffect } from 'react'

export default function MottoOverlay() {
  const [isVisible, setIsVisible] = useState(true)
  const [isAnimatingOut, setIsAnimatingOut] = useState(false)

  const hideOverlay = () => {
    setIsAnimatingOut(true)
    // Wait for animation to complete before removing from DOM
    setTimeout(() => {
      setIsVisible(false)
    }, 300)
  }

  useEffect(() => {
    // Auto-hide after 3 seconds (reduced from 5)
    const autoHideTimer = setTimeout(() => {
      hideOverlay()
    }, 3000)

    // Hide on any click, touch, or keypress
    const handleInteraction = () => {
      hideOverlay()
    }

    // Hide on scroll
    const handleScroll = () => {
      hideOverlay()
    }

    document.addEventListener('click', handleInteraction)
    document.addEventListener('touchstart', handleInteraction)
    document.addEventListener('keydown', handleInteraction)
    window.addEventListener('scroll', handleScroll)

    return () => {
      clearTimeout(autoHideTimer)
      document.removeEventListener('click', handleInteraction)
      document.removeEventListener('touchstart', handleInteraction)
      document.removeEventListener('keydown', handleInteraction)
      window.removeEventListener('scroll', handleScroll)
    }
  }, [])

  if (!isVisible) return null

  return (
    <div 
      className={`fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm transition-opacity duration-300 ${
        isAnimatingOut ? 'opacity-0' : 'opacity-100'
      }`}
    >
      <div 
        className={`text-center animate-pulse cursor-pointer transition-transform duration-300 ${
          isAnimatingOut ? 'scale-95' : 'scale-100'
        }`}
        onClick={hideOverlay}
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
          Click anywhere, scroll, or wait 3 seconds...
        </div>
      </div>
    </div>
  )
}