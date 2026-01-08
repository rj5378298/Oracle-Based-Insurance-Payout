# 🛡️ Oracle-Based Insurance Payout

A decentralized insurance smart contract that provides automatic payouts based on real-world data feeds through oracle integration.

## 🌟 Features

- 📋 **Policy Creation**: Create customizable insurance policies with specific trigger conditions
- 🔗 **Oracle Integration**: Real-time data feeds for automated claim processing  
- ⚡ **Automatic Payouts**: Smart contract automatically processes payouts when conditions are met
- 🎯 **Flexible Triggers**: Support for various operators (greater than, less than, equal to, etc.)
- 💰 **Premium Calculation**: Dynamic premium calculation based on coverage and duration
- 🚫 **Policy Cancellation**: Early cancellation with partial refund
- 🔒 **Secure Fund Management**: Owner-controlled fund withdrawal and oracle management

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- STX wallet for testing

### Installation
```bash
git clone <repository-url>
cd oracle-based-insurance-payout
clarinet console
```

## 📖 Usage

### 1. Deploy Contract
```bash
clarinet deploy
```

### 2. Set Oracle Address (Owner Only)
```clarity
(contract-call? .oracle-based-insurance-payout set-oracle-address 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### 3. Create Insurance Policy
```clarity
(contract-call? .oracle-based-insurance-payout create-policy
    u10000000  ;; coverage amount (10 STX)
    u1000      ;; duration in blocks
    u50        ;; trigger condition value
    "gt"       ;; trigger operator (greater than)
)
```

### 4. Update Oracle Data (Oracle Only)
```clarity
(contract-call? .oracle-based-insurance-payout update-oracle-data
    "weather-temp" ;; data key
    u75            ;; temperature value
)
```

### 5. Submit Insurance Claim
```clarity
(contract-call? .oracle-based-insurance-payout submit-claim
    u1             ;; policy ID
    "weather-temp" ;; oracle data key
)
```

## 🔧 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create-policy` | Create new insurance policy | coverage, duration, trigger-condition, operator |
| `submit-claim` | Submit claim for payout | policy-id, data-key |
| `cancel-policy` | Cancel active policy | policy-id |
| `update-oracle-data` | Update oracle data (oracle only) | data-key, value |
| `set-oracle-address` | Set oracle address (owner only) | new-oracle |
| `withdraw-funds` | Withdraw contract funds (owner only) | amount |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-policy` | Get policy details |
| `get-oracle-data` | Get oracle data |
| `get-contract-balance` | Get contract STX balance |
| `get-next-policy-id` | Get next available policy ID |

## 🎯 Use Cases

- 🌾 **Crop Insurance**: Automatic payouts based on weather data
- ✈️ **Flight Delay Insurance**: Claims triggered by flight status APIs
- 📈 **Price Protection**: Coverage against price volatility
- 🏠 **Property Insurance**: Weather-based damage claims
- 🔐 **Smart Contract Insurance**: Protection against contract failures

## 🧪 Testing

```bash
# Run all tests
clarinet test

# Run specific test
clarinet test tests/oracle_test.ts
```

## 🔐 Security Features

- ✅ Owner-only administrative functions
- ✅ Oracle authorization checks
- ✅ Input validation and error handling
- ✅ Reentrancy protection
- ✅ Balance checks before transfers

## 📊 Contract Parameters

- **Minimum Premium**: 5 STX
- **Oracle Fee**: 1 STX  
- **Max Payout Ratio**: 300% of coverage
- **Supported Operators**: `gt`, `lt`, `eq`, `ge`, `le`

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

Built with ❤️ using Clarity and Stacks blockchain
