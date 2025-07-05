# Pet Pat Frontend Integration Guide

## Overview

Pet Pat is a milestone-based goal achievement platform where users stake PAT tokens and grow virtual pets through validated progress. Pets evolve based on milestone completion (max 4 milestones per goal).

### Architecture
```
Frontend ↔ Smart Contracts ↔ Ponder Indexer ↔ GraphQL API
                ↕
           Pinata IPFS (Pet Metadata)
```

### Core Components
- **5 Smart Contracts**: PATToken, PatTreasuryManager, PatValidationSystem, PatNFT, PatGoalManager
- **Ponder Indexer**: Real-time event indexing with GraphQL API
- **Pinata IPFS**: Pet metadata and evidence storage

---

## Key User Flows

### 1. Goal Creation Flow (Single Transaction)
```
User Input → Metadata Upload → createGoalWithMilestones() → Pet Minted → Real-time Updates
```

**Steps:**
1. User enters goal details + milestones (max 4)
2. Frontend uploads pet metadata to Pinata
3. Call `createGoalWithMilestones()` with IPFS hash
4. Pet NFT minted automatically (EGG stage)
5. Ponder indexes events → GraphQL updates

### 2. Milestone Completion Flow
```
Evidence Upload → submitMilestone() → Validation → completeMilestone() → Pet Evolution
```

**Steps:**
1. User uploads evidence to Pinata
2. Call `submitMilestone()` with evidence IPFS hash
3. Validators approve/reject through validation system
4. Approved milestones trigger pet evolution:
   - **2 milestones** → EGG evolves to BABY
   - **4 milestones** → BABY evolves to ADULT (goal completed)

### 3. Real-time Updates Flow
```
Contract Events → Ponder Indexer → GraphQL Subscriptions → Frontend Updates
```

**Key Events to Listen:**
- `GoalCreated` → Update user dashboard
- `MilestoneCompleted` → Update progress, check evolution
- `PetEvolved` → Show evolution animation
- `GoalCompleted` → Show completion celebration

---

## Smart Contract Integration

### Contract Addresses Setup
```javascript
const CONTRACTS = {
  PAT_TOKEN: "0x...",
  PAT_TREASURY_MANAGER: "0x...",
  PAT_VALIDATION_SYSTEM: "0x...",
  PAT_NFT: "0x...",
  PAT_GOAL_MANAGER: "0x..."
};
```

### Primary Functions

#### 1. Goal Creation (Recommended - Single Transaction)
```javascript
await patGoalManager.createGoalWithMilestones(
  title,                    // string
  stakeAmount,             // uint96 (max 4 milestones)
  durationDays,            // uint32
  petName,                 // string
  petType,                 // 0=DRAGON, 1=CAT, 2=PLANT
  petMetadataIPFS,         // string (from Pinata)
  milestoneDescriptions    // string[] (max 4 descriptions)
);
```

#### 2. Token Approval (Before Goal Creation)
```javascript
await patToken.approve(
  CONTRACTS.PAT_TREASURY_MANAGER,
  stakeAmount
);
```

#### 3. Milestone Submission
```javascript
await patGoalManager.submitMilestone(
  milestoneId,            // uint256
  evidenceIPFS            // string (from Pinata)
);
```

#### 4. Validator Registration
```javascript
await patValidationSystem.registerValidator(
  stakeAmount             // uint256 (minimum 50 PAT)
);
```

#### 5. Validation Submission
```javascript
await patValidationSystem.submitValidation(
  milestoneId,            // uint256
  approve,                // bool
  comment                 // string
);
```

### Optimized Read Functions
```javascript
// Get basic goal info (gas optimized)
const [owner, stakeAmount, endTime, status, milestonesCompleted, totalMilestones] = 
  await patGoalManager.getGoalBasicInfo(goalId);

// Get pet info with milestone count
const [owner, experience, level, petType, stage, goalId, milestonesCompleted] = 
  await patNFT.getPetBasicInfo(tokenId);

// Get evolution thresholds
const [babyThreshold, adultThreshold, xpPerMilestone, bonusXP] = 
  await patNFT.getEvolutionThresholds(); // Returns: [2, 4, 25, 100]
```

---

## Pinata IPFS Integration

### Pet Metadata Structure
```javascript
const generatePetMetadata = (petData) => ({
  name: petData.name,
  description: "A Pat Pet that evolves with milestone achievements",
  image: `ipfs://${getImageHash(petData.petType, petData.stage)}`,
  attributes: [
    { trait_type: "Pet Type", value: getPetTypeName(petData.petType) },
    { trait_type: "Evolution Stage", value: getStageName(petData.stage) },
    { trait_type: "Milestones Completed", value: petData.milestonesCompleted },
    { trait_type: "Max Milestones", value: 4 },
    { trait_type: "Progress", value: `${petData.milestonesCompleted}/4` },
    { trait_type: "Goal ID", value: petData.goalId }
  ],
  properties: {
    evolution_based_on: "milestones",
    max_milestones: 4
  }
});
```

### Upload Functions
```javascript
// Upload pet metadata
const uploadMetadata = async (metadata, tokenId) => {
  const response = await fetch('https://api.pinata.cloud/pinning/pinJSONToIPFS', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'pinata_api_key': PINATA_CONFIG.apiKey,
      'pinata_secret_api_key': PINATA_CONFIG.secretKey
    },
    body: JSON.stringify({
      pinataContent: metadata,
      pinataMetadata: { name: `pet-${tokenId}-metadata` }
    })
  });
  return (await response.json()).IpfsHash;
};

// Upload evidence file
const uploadEvidence = async (file) => {
  const formData = new FormData();
  formData.append('file', file);
  // ... Pinata upload logic
  return ipfsHash;
};
```

---

## Ponder GraphQL Integration

### Essential Queries

#### User Dashboard
```graphql
query GetUserGoals($userAddress: String!) {
  goalCreateds(where: { owner: $userAddress }, orderBy: timestamp, orderDirection: desc) {
    goalId
    petTokenId
    params_stakeAmount
    params_totalMilestones
    timestamp
  }
  
  goalCompleteds(where: { owner: $userAddress }) {
    goalId
    packedRewards
    timestamp
  }
}
```

#### Goal Progress
```graphql
query GetGoalProgress($goalId: String!) {
  milestoneCreateds(where: { goalId: $goalId }, orderBy: timestamp) {
    milestoneId
    description
  }
  
  milestoneCompleteds(where: { goalId: $goalId }, orderBy: timestamp) {
    milestoneId
    packedData  # Contains: xp(16) | completed(16) | total(16) | progress(16)
    timestamp
  }
}
```

#### Pet Evolution History
```graphql
query GetPetEvolution($tokenId: String!) {
  petEvolveds(where: { tokenId: $tokenId }, orderBy: timestamp) {
    packedData  # Contains: fromStage(8) | toStage(8) | milestones(8) | totalExp(64)
    newMetadataIPFSHash
    timestamp
  }
  
  milestoneCompleteds(where: { tokenId: $tokenId }) {
    packedData
    newMetadataIPFSHash
    timestamp
  }
}
```

### Real-time Subscriptions
```graphql
subscription GoalEvents($userAddress: String!) {
  milestoneCompleteds(where: { goalOwner: $userAddress }) {
    goalId
    milestoneId
    packedData
    timestamp
  }
  
  petEvolveds(where: { owner: $userAddress }) {
    tokenId
    packedData
    timestamp
  }
  
  goalCompleteds(where: { owner: $userAddress }) {
    goalId
    packedRewards
    timestamp
  }
}
```

### Data Unpacking Helpers
```javascript
// Unpack milestone completion data
const unpackMilestoneData = (packedData) => ({
  xpAwarded: Number((packedData >> 240n) & 0xFFFFn),
  milestonesCompleted: Number((packedData >> 224n) & 0xFFFFn),
  totalMilestones: Number((packedData >> 208n) & 0xFFFFn),
  progressPercentage: Number((packedData >> 192n) & 0xFFFFn)
});

// Unpack pet evolution data
const unpackEvolutionData = (packedData) => ({
  fromStage: Number((packedData >> 248n) & 0xFFn),
  toStage: Number((packedData >> 240n) & 0xFFn),
  milestonesCompleted: Number((packedData >> 232n) & 0xFFn),
  totalExperience: Number((packedData >> 168n) & ((1n << 64n) - 1n))
});
```

---

## Event Handling

### Key Events to Monitor

#### Milestone Progress
```javascript
// Listen for milestone completion
patGoalManager.on('MilestoneCompleted', (milestoneId, goalId, goalOwner, packedData, petMetadataIPFS, timestamp) => {
  const { milestonesCompleted, progressPercentage } = unpackMilestoneData(packedData);
  
  // Update progress bar
  updateProgressBar(progressPercentage);
  
  // Check for evolution triggers
  if (milestonesCompleted === 2) {
    showEvolutionAlert("Your pet is evolving to BABY! 🐣");
  } else if (milestonesCompleted === 4) {
    showEvolutionAlert("Your pet is evolving to ADULT! 🦸");
  }
});
```

#### Pet Evolution
```javascript
// Listen for pet evolution
patNFT.on('PetEvolved', (tokenId, goalId, owner, packedData, newMetadataIPFS, timestamp) => {
  const { fromStage, toStage, milestonesCompleted } = unpackEvolutionData(packedData);
  
  // Show evolution animation
  showEvolutionAnimation(fromStage, toStage);
  
  // Update pet display
  updatePetDisplay(newMetadataIPFS);
});
```

---

## Evolution System

### Milestone-Based Evolution
```javascript
const EVOLUTION_SYSTEM = {
  MAX_MILESTONES: 4,
  THRESHOLDS: {
    EGG_TO_BABY: 2,    // Evolve at 2 milestones (50% complete)
    BABY_TO_ADULT: 4   // Evolve at 4 milestones (100% complete)
  },
  XP: {
    PER_MILESTONE: 25,
    COMPLETION_BONUS: 100
  }
};

// Evolution prediction
const predictEvolution = (currentMilestones) => {
  if (currentMilestones >= 4) return { stage: 'ADULT', progress: 100 };
  if (currentMilestones >= 2) return { stage: 'BABY', progress: 50 + (currentMilestones - 2) * 25 };
  return { stage: 'EGG', progress: currentMilestones * 25 };
};
```

### Pet Types & Stages
```javascript
const PET_TYPES = {
  0: { name: 'Dragon', emoji: '🐉' },
  1: { name: 'Cat', emoji: '🐱' },
  2: { name: 'Plant', emoji: '🌱' }
};

const EVOLUTION_STAGES = {
  0: { name: 'EGG', emoji: '🥚', description: 'Starting your journey' },
  1: { name: 'BABY', emoji: '👶', description: 'Halfway to your goal!' },
  2: { name: 'ADULT', emoji: '🦸', description: 'Goal achieved!' }
};
```

---

## Error Handling

### Common Error Patterns
```javascript
// Transaction error handler
const handleTransactionError = (error, operation) => {
  if (error.code === 'INSUFFICIENT_FUNDS') {
    showError('Insufficient ETH for gas fees');
  } else if (error.message.includes('TooManyMilestones')) {
    showError('Maximum 4 milestones allowed per goal');
  } else if (error.message.includes('MaxMilestonesReached')) {
    showError('Cannot add more milestones to this goal');
  } else {
    showError(`${operation} failed: ${error.message}`);
  }
};

// Validation before transactions
const validateGoalCreation = async (milestones, stakeAmount) => {
  if (milestones.length > 4) throw new Error('Maximum 4 milestones allowed');
  if (milestones.length === 0) throw new Error('At least 1 milestone required');
  
  const balance = await patToken.balanceOf(userAddress);
  if (balance.lt(stakeAmount)) throw new Error('Insufficient PAT balance');
};
```

---

## Quick Reference

### Contract Functions Summary
| Function | Purpose | Max Milestones |
|----------|---------|----------------|
| `createGoalWithMilestones()` | Create goal + milestones (single tx) | 4 |
| `submitMilestone()` | Submit evidence for validation | - |
| `completeMilestone()` | Complete milestone (admin/validator) | - |
| `getPetBasicInfo()` | Get pet data including milestones | - |
| `getEvolutionThresholds()` | Get evolution milestones (2, 4) | - |

### Evolution Checkpoints
- **0-1 milestones**: EGG stage 🥚
- **2-3 milestones**: BABY stage 👶 (evolves at milestone 2)
- **4 milestones**: ADULT stage 🦸 (evolves at milestone 4, goal completed)

### Key Constants
- **Maximum milestones per goal**: 4
- **XP per milestone**: 25
- **Completion bonus**: 100 XP
- **Evolution triggers**: Milestone count (not XP)

---

## Support

### Common Issues
1. **Pet not evolving**: Check milestone completion count (2 for BABY, 4 for ADULT)
2. **Transaction fails**: Verify milestone count ≤ 4 and sufficient PAT balance
3. **Metadata not updating**: Ensure Pinata upload success before contract calls
4. **GraphQL errors**: Confirm Ponder indexer is synced

**Remember**: Evolution is milestone-based, making it predictable and goal-oriented! 🎯