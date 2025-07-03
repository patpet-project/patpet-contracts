# Pet Pat 🐾

> A gamified goal achievement platform where your virtual pets grow with your success

Pet Pat combines Web3 incentives with emotional engagement through virtual pets that evolve based on your goal completion progress. Stake PAT tokens, set milestones, submit evidence, and watch your pet companion grow as you achieve your dreams.

## 🎯 Overview

Pet Pat is a decentralized goal achievement platform that uses:
- **Staking Mechanics**: Put PAT tokens at risk to create commitment
- **Virtual Pet NFTs**: Dynamic companions that evolve with your progress  
- **Community Validation**: Decentralized milestone verification system
- **Tiered Rewards**: Higher stakes unlock better reward multipliers
- **Emotional Gamification**: Pet mood and evolution create psychological investment

## 🏗️ Architecture

```
Frontend ↔ Smart Contracts ↔ Ponder Indexer ↔ GraphQL API
                ↕
           Pinata IPFS (Metadata)
```

### Smart Contract System

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **PATToken** | ERC20 utility token | Burn mechanics, reward distribution, max 100M supply |
| **PatGoalManager** | Goal lifecycle management | Creates goals, tracks milestones, handles completion/failure |
| **PatNFT** | Dynamic pet NFTs | 3 types, 3 evolution stages, mood system, XP tracking |
| **PatTreasuryManager** | Tokenomics & rewards | 5-tier reward system, pool distribution, stake management |
| **PatValidationSystem** | Community governance | Validator staking, reputation scoring, decentralized validation |

## 🚀 Core Features

### Goal Creation Flow
1. **Stake PAT Tokens** (10-50,000 PAT based on tier)
2. **Choose Pet Type** (Dragon 🐉, Cat 🐱, or Plant 🌱)
3. **Set Milestones** with clear success criteria
4. **Receive Pet NFT** in "Egg" stage

### Milestone Progress
1. **Submit Evidence** (photos, documents, proof of work)
2. **Community Validation** (3-7 validators based on stake size)
3. **Earn XP** (25 XP per approved milestone)
4. **Pet Evolution** (Egg → Baby at 100 XP, Baby → Adult at 500 XP)

### Reward System
| Stake Tier | PAT Range | Reward Multiplier | Tier Name |
|------------|-----------|-------------------|-----------|
| Tier 1 | 10-99 PAT | 110% | Sprout 🌱 |
| Tier 2 | 100-499 PAT | 125% | Bloom 🌸 |
| Tier 3 | 500-1,999 PAT | 150% | Flourish 🌺 |
| Tier 4 | 2,000-9,999 PAT | 200% | Thrive 🌳 |
| Tier 5 | 10,000+ PAT | 300% | Legend 🏆 |

## 🎮 Pet System

### Pet Types & Evolution
```
🥚 EGG STAGE (0-99 XP)
    ↓ (100 XP threshold)
👶 BABY STAGE (100-499 XP)  
    ↓ (500 XP threshold)
🦸 ADULT STAGE (500+ XP)
```

### Pet Characteristics
- **Dynamic Metadata**: Appearance changes with evolution and mood
- **Mood System**: Happy pets for success, sad pets for setbacks
- **Experience Points**: Earned through milestone completion
- **Rarity Traits**: Based on evolution stage and achievements

### Pet Types
- **🐉 Dragon**: Mythical companion for ambitious goals
- **🐱 Cat**: Loyal friend for personal development
- **🌱 Plant**: Growing companion for habit formation

## 💰 Tokenomics

### PAT Token Distribution
- **Total Supply**: 100,000,000 PAT
- **Initial Mint**: 50,000,000 PAT
- **Remaining**: Minted through rewards and platform growth

### Treasury Pool Allocation (from failed stakes)
- **60% Reward Pool**: Future goal completion bonuses
- **25% Insurance Pool**: Platform stability and edge cases  
- **10% Validator Pool**: Community validation rewards
- **5% Development Pool**: Platform development and maintenance
- **10% Burned**: Deflationary pressure (from failed stakes)

### Validator Economics
- **Minimum Stake**: 50 PAT to become validator
- **Base Reward**: 5 PAT per validation
- **Accuracy Bonus**: +25% for correct validations
- **Reputation System**: Score affects assignment probability

## 🛠️ Technical Stack

### Frontend
- **React/Next.js**: Modern web interface
- **Web3 Integration**: Wallet connection and transaction handling
- **Pinata IPFS**: Decentralized file storage
- **GraphQL**: Real-time data from Ponder indexer

### Backend Infrastructure
- **Ponder Indexer**: Real-time blockchain event indexing
- **GraphQL API**: Optimized data queries
- **Pinata**: IPFS metadata and file storage
- **Smart Contracts**: On-chain logic and state management

### Data Flow
1. **Write Operations**: Direct smart contract interactions
2. **Read Operations**: Ponder GraphQL queries (no contract calls)
3. **Real-time Updates**: Event-driven UI updates
4. **Metadata Storage**: Dynamic IPFS uploads via Pinata

## 🔧 Development Setup

### Prerequisites
```bash
node >= 18.0.0
npm >= 8.0.0
```

### Installation
```bash
# Clone repository
git clone https://github.com/your-org/pet-pat
cd pet-pat

# Install dependencies
npm install

# Setup environment variables
cp .env.example .env.local
```

### Environment Variables
```bash
# Blockchain
NEXT_PUBLIC_CHAIN_ID=1
NEXT_PUBLIC_RPC_URL=your_rpc_url

# Contract Addresses
NEXT_PUBLIC_PAT_TOKEN_ADDRESS=0x...
NEXT_PUBLIC_GOAL_MANAGER_ADDRESS=0x...
NEXT_PUBLIC_PET_NFT_ADDRESS=0x...
NEXT_PUBLIC_TREASURY_MANAGER_ADDRESS=0x...
NEXT_PUBLIC_VALIDATION_SYSTEM_ADDRESS=0x...

# Pinata IPFS
NEXT_PUBLIC_PINATA_API_KEY=your_api_key
NEXT_PUBLIC_PINATA_SECRET_KEY=your_secret_key

# Ponder GraphQL
NEXT_PUBLIC_PONDER_API_URL=your_ponder_endpoint
```

### Local Development
```bash
# Start development server
npm run dev

# Run tests
npm run test

# Build for production
npm run build
```

## 📊 Smart Contract Functions

### Key Write Functions
```solidity
// PatGoalManager
createGoal(title, stakeAmount, durationDays, petName, petType, metadataIPFS, totalMilestones)
createMilestone(goalId, description)
submitMilestone(milestoneId, evidenceIPFS)

// PATToken  
approve(spender, amount) // Before creating goals
transfer(to, amount)

// PatValidationSystem
registerValidator(stakeAmount)
submitValidation(milestoneId, approve, comment)
```

### GraphQL Queries
```graphql
# Get user goals
query GetUserGoals($userAddress: String!) {
  goalCreateds(where: { owner: $userAddress }) {
    goalId
    title
    stakeAmount
    petTokenId
    status
  }
}

# Get pet details
query GetPetDetails($tokenId: String!) {
  petMinteds(where: { tokenId: $tokenId }) {
    name
    petType
    goalId
    metadataIPFS
  }
  
  petEvolveds(where: { tokenId: $tokenId }) {
    fromStage
    toStage
    timestamp
  }
}
```

## 🔐 Security Features

### Smart Contract Security
- **OpenZeppelin Standards**: Battle-tested contract libraries
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Access Control**: Role-based permissions
- **Pausable**: Emergency stop functionality

### Validation Security
- **Multi-validator Consensus**: Prevents single point of failure
- **Reputation Scoring**: Incentivizes honest behavior
- **Stake-based Participation**: Economic alignment
- **Time-bounded Validation**: Prevents indefinite delays

## 🚦 Deployment

### Contract Deployment Order
1. Deploy **PATToken**
2. Deploy **PatTreasuryManager** (with PATToken address)
3. Deploy **PatValidationSystem** (with PATToken, Treasury addresses)
4. Deploy **PatNFT**
5. Deploy **PatGoalManager** (with all contract addresses)
6. Set authorizations between contracts

### Post-Deployment Setup
```solidity
// Authorize contracts
patToken.addAuthorizedMinter(treasuryManager.address)
patToken.addAuthorizedBurner(treasuryManager.address)
petNFT.setAuthorizedContract(goalManager.address, true)
treasuryManager.addAuthorizedContract(goalManager.address)
validationSystem.addAuthorizedContract(goalManager.address)
```

## 📈 Roadmap

### Phase 1: Core Platform ✅
- [x] Smart contract development
- [x] Basic pet system
- [x] Goal creation and tracking
- [x] Community validation

### Phase 2: Enhanced Features 🚧
- [ ] Mobile app
- [ ] Advanced pet customization
- [ ] Social features and leaderboards
- [ ] Integration with fitness trackers

### Phase 3: Ecosystem Expansion 🔮
- [ ] Cross-chain deployment
- [ ] Partner integrations
- [ ] DAO governance
- [ ] Marketplace for pet accessories

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow
1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Website**: https://petpat.xyz
- **Documentation**: https://docs.petpat.xyz
- **Discord**: https://discord.gg/petpat
- **Twitter**: https://twitter.com/petpatxyz
- **GitHub**: https://github.com/petpat-xyz

## ⚡ Quick Start

1. **Connect Wallet** to the Pet Pat dApp
2. **Get PAT Tokens** from DEX or faucet
3. **Create Your First Goal** with a 30-day timeline
4. **Choose Your Pet** (Dragon, Cat, or Plant)
5. **Set Milestones** with clear success criteria
6. **Submit Evidence** as you make progress
7. **Watch Your Pet Grow** with each completed milestone
8. **Complete Goal** and earn rewards + fully evolved pet!

---

**Built with ❤️ by the Pet Pat Team**

*Making goal achievement fun, rewarding, and emotionally engaging through the power of virtual companions and Web3 incentives.*