# 🎓 Peer Tutoring Credit System

A decentralized platform that incentivizes peer-to-peer academic help through on-chain credits.

## 🌟 Features

- Register as a tutor
- Start and complete tutoring sessions
- Earn credits for tutoring time
- Rate tutoring sessions
- Transfer tutoring credits
- Track tutor ratings and performance

## 💡 How It Works

1. **Tutor Registration**
   - Anyone can register as a tutor
   - Initial rating of 5 stars
   - Can set active/inactive status

2. **Session Management**
   - Start sessions with specified duration
   - Minimum session duration: 30 minutes
   - Credits awarded based on duration (10 credits per hour)

3. **Credit System**
   - Credits automatically minted upon session completion
   - Transferable between users
   - Can be used for various educational rewards

4. **Rating System**
   - Students can rate completed sessions (1-5 stars)
   - Tutor ratings updated automatically
   - Helps maintain teaching quality

## 🔧 Usage

### Register as Tutor
```clarity
(contract-call? .peer-tutoring-credit-system register-as-tutor)
```

### Start Session
```clarity
(contract-call? .peer-tutoring-credit-system start-tutoring-session 'STUDENT_ADDRESS u60)
```

### Complete Session
```clarity
(contract-call? .peer-tutoring-credit-system complete-session u1)
```

### Rate Session
```clarity
(contract-call? .peer-tutoring-credit-system rate-session u1 u5)
```

## 📊 Contract Information

- Token: `tutoring-credit`
- Credit Rate: 10 credits per hour
- Minimum Session: 30 minutes
```
