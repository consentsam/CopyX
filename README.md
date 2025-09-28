# CopyX - Privacy-Preserving Copy Trading Platform

CopyX is a revolutionary decentralized copy trading platform that leverages Fully Homomorphic Encryption (FHE) to enable privacy-preserving trade execution on Ethereum. Built on EigenLayer's AVS infrastructure, it combines encrypted intent processing with automated market making through Uniswap V4 hooks.

## 🏗️ Architecture Overview

CopyX consists of three main components working in harmony:

### 1. **Universal Privacy Hook (Uniswap V4)**
- Custom hook that intercepts swap operations
- Batches encrypted trading intents using FHE
- Manages liquidity pools with 80/20 vault allocation strategy
- Enables privacy-preserving order matching without revealing trade details

### 2. **SwapManager AVS (EigenLayer)**
- Decentralized operator network for processing encrypted intents
- Uses **Pyth Entropy** for verifiable randomness in operator selection
- Implements Universal Encrypted Intent (UEI) framework
- Consensus-based settlement with multi-operator attestation

### 3. **SimpleBoringVault**
- Strategy execution vault with **Pyth Price Oracle** integration
- USD-based accounting system (not token-based)
- Real-time price feeds for accurate portfolio valuation
- Manages 80% of liquidity for copy trading strategies

## 🔐 Key Technologies

### **Fully Homomorphic Encryption (FHE)**
- **@zama-ai/fhevm**: Enables computation on encrypted data
- Trade amounts and parameters remain encrypted throughout execution
- Zero-knowledge privacy for all trading activities

### **Pyth Network Integration**
- **Pyth Entropy**: Provides verifiable randomness for fair operator selection
  - Replaces predictable block hash randomness
  - Ensures unbiased, manipulation-resistant operator committee formation
  - Asynchronous callback mechanism for true randomness

- **Pyth Price Oracles**: Real-time price feeds for USD-based accounting
  - Accurate portfolio valuation across multiple tokens
  - Protection against price manipulation
  - Sub-second price updates with confidence intervals

### **Uniswap V4 Hooks**
- Custom `UniversalPrivacyHook` for encrypted swap processing
- Batch settlement mechanism for gas efficiency
- Internal balance tracking for reduced on-chain transactions
- Seamless integration with existing Uniswap V4 liquidity

### **EigenLayer AVS**
- Decentralized operator network with stake-based security
- ECDSA-based consensus mechanism
- Slashable security guarantees
- Restaked ETH for enhanced economic security

## 🚀 Features

- **Privacy-First Trading**: All trade details remain encrypted
- **Copy Trading**: Follow successful traders without revealing strategies
- **Fair Operator Selection**: Pyth Entropy ensures unbiased randomness
- **USD-Based Accounting**: Accurate portfolio tracking with Pyth oracles
- **Batch Processing**: Gas-efficient settlement of multiple trades
- **Decentralized Execution**: No single point of failure or control

## 📋 Requirements

- Node.js v18+
- Hardhat
- MetaMask browser extension
- Foundry (for contract development)

## 🛠️ Installation

```bash
# Clone the repository
git clone https://github.com/consentsam/CopyX.git
cd CopyX

# Install dependencies
npm install

# Install Pyth SDK
npm install @pythnetwork/pyth-sdk-solidity
npm install @pythnetwork/entropy-sdk-solidity
```

## 🔧 Configuration

### Local Development

1. **Start Hardhat Node**:
```bash
npm run hardhat-node
```

2. **Deploy Contracts**:
```bash
npm run deploy:local
```

3. **Configure MetaMask**:
- Network Name: Hardhat
- RPC URL: http://127.0.0.1:8545
- Chain ID: 31337
- Currency: ETH

### Testnet Deployment (Sepolia)

1. **Set Environment Variables**:
```bash
cp .env.example .env
# Add your MNEMONIC, INFURA_API_KEY, PYTH_ENDPOINT
```

2. **Deploy to Sepolia**:
```bash
npm run deploy:sepolia
```

## 📁 Project Structure

```
CopyX/
├── packages/
│   ├── hello-world-avs/       # AVS and smart contracts
│   │   ├── contracts/
│   │   │   ├── SwapManager.sol      # AVS with Pyth Entropy
│   │   │   ├── SimpleBoringVault.sol # Vault with Pyth Oracles
│   │   │   └── UniversalPrivacyHook.sol
│   │   └── scripts/
│   ├── fhevm-hardhat-template/ # FHE contract templates
│   └── site/                    # React frontend
│       ├── fhevm/              # FHE integration hooks
│       └── hooks/              # React hooks for contract interaction
```

## 🔑 Smart Contract Addresses

### Mainnet (Coming Soon)
- SwapManager AVS: `TBD`
- UniversalPrivacyHook: `TBD`
- SimpleBoringVault: `TBD`

### Sepolia Testnet
- SwapManager AVS: `0x...`
- Pyth Entropy: `0x41c9e39574F40Ad34c79f1C99B66A45eFB830d4c`
- Pyth Oracle: `0x694AA1769357215DE4FAC081bf1f309aDC325306`

## 🧪 Testing

```bash
# Run unit tests
npm test

# Run integration tests
npm run test:integration

# Test with coverage
npm run coverage
```

## 📊 How It Works

1. **User submits encrypted trade intent** → FHE ensures privacy
2. **Hook batches intents** → Reduces gas costs
3. **Pyth Entropy selects operators** → Fair, random selection
4. **Operators decrypt and match orders** → Off-chain processing
5. **Consensus on settlement** → Multi-operator attestation
6. **Pyth oracles calculate USD values** → Accurate pricing
7. **Vault executes trades** → On-chain settlement

## 🛡️ Security Features

- **FHE Encryption**: Trade details never exposed
- **Pyth Entropy Randomness**: Manipulation-resistant operator selection
- **Multi-Operator Consensus**: No single point of trust
- **Pyth Price Oracles**: Tamper-resistant price feeds
- **EigenLayer Slashing**: Economic security guarantees

## 📚 Documentation

- [Architecture Overview](./docs/architecture.md)
- [FHE Integration Guide](./docs/fhe-guide.md)
- [Pyth Integration](./docs/pyth-integration.md)
- [AVS Operator Guide](./docs/operator-guide.md)

## 🔗 External Documentation

- [Zama FHEVM Documentation](https://docs.zama.ai/protocol/solidity-guides/)
- [Pyth Network Documentation](https://docs.pyth.network/)
- [Uniswap V4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [EigenLayer Documentation](https://docs.eigenlayer.xyz/)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the BSD-3-Clause-Clear License - see the [LICENSE](LICENSE) file for details.

## 🌐 Community

- [Discord](https://discord.gg/copyx)
- [Twitter](https://twitter.com/copyxprotocol)
- [GitHub Issues](https://github.com/consentsam/CopyX/issues)

## ⚠️ Disclaimer

CopyX is currently in development. Use at your own risk. Always verify contract addresses and conduct your own research before interacting with the protocol.