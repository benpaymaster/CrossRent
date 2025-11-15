# 🎯 Arc RentCredit Demo - User Testing Guide

## Quick Start
**Demo URL**: `http://localhost:8081`

## 🧪 Testing Instructions

### **Phase 1: Tenant Experience**
1. **Create Circle Wallet**
   - Click "Create Circle Wallet" 
   - Watch wallet creation process
   - Note your wallet address (starts with 0x...)

2. **Fund Your Wallet**
   - Demo funding: $100 USDC automatically added
   - Verify balance in dashboard

3. **Create Rental Escrow**
   - Click "Create New Escrow"
   - Fill in landlord address: `0x742d35Cc6ABfcC2dC1D7825c0f2C59d1234567AB`
   - Set deposit: $500, monthly rent: $1200
   - Duration: 6 months
   - Submit escrow

4. **Make Rent Payment**
   - Click "Pay Rent" on your escrow
   - Watch Circle bridge transaction
   - Verify payment confirmation

### **Phase 2: Dual-Perspective Demo**
5. **Switch to Landlord View**
   - Click "🏠 Landlord View" in header
   - Watch perspective change

6. **View Payment Notifications**
   - See "💰 Recent Payment Notifications" section
   - Verify your payment appears in landlord dashboard
   - Check real-time transaction details

7. **Test Real-time Sync**
   - Switch back to "👤 Tenant View"
   - Make another rent payment
   - Switch to "🏠 Landlord View" again
   - Verify new payment notification appears

### **Phase 3: Feedback**
8. **Submit Feedback**
   - Click "📝 Give Feedback" in header
   - Rate your experience (1-5 stars)
   - Select favorite features
   - Add comments
   - Submit feedback

9. **Verify Social Proof**
   - Watch user stats update in header
   - See new rating reflected

## 🎬 **Key Features to Test**

✅ **Circle Programmable Wallets**: Dev-controlled wallet creation  
✅ **CCTP Cross-Chain Bridge**: Seamless USDC transfers  
✅ **Dual Perspective**: Tenant ↔ Landlord view switching  
✅ **Real-time Notifications**: Payment confirmations  
✅ **Smart Contract Integration**: Escrow management  
✅ **Social Proof**: User feedback and ratings  

## 💡 **What to Look For**

- **Smooth UX**: No MetaMask popups, wallet handled automatically
- **Real-time Updates**: Instant notifications between perspectives  
- **Professional UI**: Clean, modern interface design
- **Complete Ecosystem**: End-to-end rental transaction flow
- **Social Validation**: User engagement and feedback system

## 🚀 **Demo Success Criteria**

- [x] Wallet created and funded
- [x] Escrow created successfully  
- [x] Rent payment processed
- [x] Landlord receives payment notification
- [x] Perspective switching works smoothly
- [x] Feedback submitted successfully

---

**Questions or Issues?** Let me know what you think about this rental ecosystem demo!

**Expected Demo Time**: ~5 minutes for complete flow