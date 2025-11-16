"use client";

import React, { useState } from "react";

const steps = [
  {
    title: "Welcome to CrossRent!",
    description:
      "Pay rent globally with USDC, build your reputation, and never worry about crypto complexity. Let's get started!",
    icon: "🏠",
  },
  {
    title: "Automatic Wallet Creation",
    description:
      "No crypto wallet needed! We create a secure USDC wallet for you automatically when you pay rent.",
    icon: "🔑",
  },
  {
    title: "Pay Rent Instantly",
    description:
      "Just enter your property address and rent amount. Payments are instant, global, and secure.",
    icon: "💸",
  },
  {
    title: "Build Your Reputation",
    description:
      "Every on-time payment increases your on-chain rental reputation. Landlords love reliable tenants!",
    icon: "🌟",
  },
  {
    title: "Try the CCTP Demo!",
    description:
      "Experience cross-chain USDC transfers with our Circle CCTP demo. It's fast, secure, and easy.",
    icon: "🌉",
  },
];

export default function OnboardingModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const [step, setStep] = useState(0);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-60">
      <div className="bg-white rounded-2xl shadow-2xl max-w-md w-full p-8 relative animate-fadeIn">
        <button
          className="absolute top-4 right-4 text-gray-400 hover:text-gray-700 text-2xl font-bold"
          onClick={onClose}
          aria-label="Close onboarding"
        >
          ×
        </button>
        <div className="flex flex-col items-center text-center">
          <div className="text-5xl mb-4">{steps[step].icon}</div>
          <h2 className="text-2xl font-bold mb-2 text-gray-900">{steps[step].title}</h2>
          <p className="text-gray-600 mb-6">{steps[step].description}</p>
          <div className="flex space-x-2 mb-6">
            {steps.map((_, i) => (
              <span
                key={i}
                className={`w-3 h-3 rounded-full ${i === step ? "bg-blue-600" : "bg-gray-300"}`}
              />
            ))}
          </div>
          <div className="flex w-full justify-between">
            <button
              className="px-4 py-2 rounded-lg bg-gray-200 text-gray-700 font-medium disabled:opacity-50"
              onClick={() => setStep((s) => Math.max(0, s - 1))}
              disabled={step === 0}
            >
              Back
            </button>
            {step < steps.length - 1 ? (
              <button
                className="px-6 py-2 rounded-lg bg-blue-600 text-white font-semibold hover:bg-blue-700 transition"
                onClick={() => setStep((s) => Math.min(steps.length - 1, s + 1))}
              >
                Next
              </button>
            ) : (
              <button
                className="px-6 py-2 rounded-lg bg-green-600 text-white font-semibold hover:bg-green-700 transition"
                onClick={onClose}
              >
                Get Started
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
