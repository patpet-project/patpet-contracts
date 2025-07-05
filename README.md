# Pet Pat MVP Integration Guide

## Overview

Pet Pat is a milestone-based goal achievement platform where users stake PAT tokens and grow virtual pets through milestone completion. Pets evolve based on progress (max 4 milestones per goal).

### Core Architecture
```
Frontend ↔ Clean Contract Events ↔ Ponder Indexer ↔ GraphQL API
                ↕
        Pinata IPFS (Pet Metadata & Evidence)
```

### Key Components
- **5 Smart Contracts**: Clean events, no packed data
- **Ponder Indexer**: Real-time indexing with GraphQL
- **Pinata SDK**: IPFS storage for metadata and evidence

---

## MVP User Flows

### 1. 🎯 Goal Creation Flow (Primary MVP Flow)
```
Goal Input → Pet Metadata Upload → createGoalWithMilestones() → Pet Minted → Dashboard Update
```

**Steps:**
1. User fills goal form with 1-4 milestones
2. Frontend generates and uploads pet metadata to Pinata
3. Single transaction: `createGoalWithMilestones()` 
4. Pet NFT auto-minted in EGG stage
5. Real-time dashboard update via GraphQL

### 2. 📋 Milestone Submission Flow
```
Evidence Upload → submitMilestone() → Validation Request → Dashboard Shows "Pending"
```

**Steps:**
1. User uploads evidence (image/video) to Pinata
2. Call `submitMilestone()` with evidence IPFS hash
3. Validation system assigns 3-7 validators automatically
4. Dashboard shows milestone as "Pending Validation"

### 3. ✅ Validation & Evolution Flow
```
Validator Decision → completeMilestone() → Pet Evolution → Celebration
```

**Steps:**
1. Validators approve/reject milestone
2. Approved milestones trigger `completeMilestone()`
3. Pet evolves at checkpoints:
   - **2 milestones** → EGG → BABY 🐣
   - **4 milestones** → BABY → ADULT 🦸 (Goal Complete!)
4. Show evolution animation + rewards

---

## Smart Contract Integration

### Contract Setup
```javascript
// Contract addresses and ABIs
const CONTRACTS = {
  PAT_TOKEN: "0x...",
  PAT_GOAL_MANAGER: "0x...",
  PAT_NFT: "0x...",
  PAT_VALIDATION_SYSTEM: "0x...",
  PAT_TREASURY_MANAGER: "0x..."
};

// Initialize with Wagmi/Viem
import { useWriteContract, useReadContract } from 'wagmi';
```

### Core Functions (MVP Priority)

#### 1. Create Goal with Milestones (Single Transaction)
```javascript
const { writeContract: createGoal } = useWriteContract();

const handleCreateGoal = async (goalData) => {
  // 1. Upload pet metadata to Pinata first
  const metadataIPFS = await uploadPetMetadata(goalData);
  
  // 2. Create goal with milestones
  await createGoal({
    address: CONTRACTS.PAT_GOAL_MANAGER,
    abi: PAT_GOAL_MANAGER_ABI,
    functionName: 'createGoalWithMilestones',
    args: [
      goalData.title,                    // string
      parseEther(goalData.stakeAmount),  // uint256
      goalData.durationDays,             // uint32
      goalData.petName,                  // string
      goalData.petType,                  // 0=DRAGON, 1=CAT, 2=PLANT
      metadataIPFS,                      // string (from Pinata)
      goalData.milestoneDescriptions     // string[] (max 4)
    ]
  });
};
```

#### 2. Submit Milestone Evidence
```javascript
const { writeContract: submitMilestone } = useWriteContract();

const handleSubmitMilestone = async (milestoneId, evidenceFile) => {
  // 1. Upload evidence to Pinata
  const evidenceIPFS = await uploadEvidence(evidenceFile);
  
  // 2. Submit milestone
  await submitMilestone({
    address: CONTRACTS.PAT_GOAL_MANAGER,
    abi: PAT_GOAL_MANAGER_ABI,
    functionName: 'submitMilestone',
    args: [milestoneId, evidenceIPFS]
  });
};
```

#### 3. Key Read Functions
```javascript
// Get goal info
const { data: goalInfo } = useReadContract({
  address: CONTRACTS.PAT_GOAL_MANAGER,
  abi: PAT_GOAL_MANAGER_ABI,
  functionName: 'getGoalFullInfo',
  args: [goalId]
});

// Get pet info  
const { data: petInfo } = useReadContract({
  address: CONTRACTS.PAT_NFT,
  abi: PAT_NFT_ABI,
  functionName: 'getPetFullInfo',
  args: [tokenId]
});

// Get evolution thresholds
const { data: evolution } = useReadContract({
  address: CONTRACTS.PAT_NFT,
  abi: PAT_NFT_ABI,
  functionName: 'getEvolutionThresholds'
});
// Returns: [2, 4, 25, 100] = [babyThreshold, adultThreshold, xpPerMilestone, bonusXP]
```

---

## Pinata Integration (Simplified)

### Setup Pinata SDK
```javascript
import { PinataSDK } from "pinata";

const pinata = new PinataSDK({
  pinataJwt: process.env.NEXT_PUBLIC_PINATA_JWT,
  pinataGateway: "your-gateway.mypinata.cloud",
});
```

### Pet Metadata Upload
```javascript
const uploadPetMetadata = async (goalData) => {
  const metadata = {
    name: goalData.petName,
    description: `${goalData.petName} is a ${getPetTypeName(goalData.petType)} companion in the Egg stage. A mysterious egg filled with potential, waiting to hatch. This Pet Pat grows stronger with each milestone achievement and evolves based on progress towards goals.`,
    image: getPetImageUrl(goalData.petType, 'EGG'),
    external_url: `https://patpet.xyz/goal/${goalData.goalId}`,
    animation_url: getPetSpriteUrl(goalData.petType),
    attributes: [
      { trait_type: "Pet Type", value: getPetTypeName(goalData.petType) },
      { trait_type: "Evolution Stage", value: "Egg" },
      { trait_type: "Level", value: 1 },
      { trait_type: "Experience", value: 0 },
      { trait_type: "Milestones Completed", value: 0 },
      { trait_type: "Total Milestones", value: goalData.milestoneDescriptions.length },
      { trait_type: "Progress", value: "0%" },
      { trait_type: "Goal ID", value: goalData.goalId },
      { trait_type: "Rarity", value: "Common" },
      { trait_type: "Element", value: getPetElement(goalData.petType) },
      { trait_type: "Mood", value: "Happy" },
      { trait_type: "Birth Time", value: Date.now() }
    ],
    properties: {
      pet_type: getPetTypeKey(goalData.petType),
      evolution_stage: "EGG",
      sprite_url: getPetSpriteUrl(goalData.petType),
      created_at: Date.now(),
      version: "1.0.0",
      milestone_based_evolution: true
    }
  };

  const upload = await pinata.upload.public
    .json(metadata)
    .name(`${goalData.petName}-metadata.json`)
    .keyvalues({
      type: 'pet_metadata',
      pet_name: goalData.petName,
      pet_type: getPetTypeKey(goalData.petType),
      evolution_stage: 'EGG',
      token_id: 'new',
      timestamp: Date.now().toString(),
      version: '1.0.0'
    });
    
  return upload.cid;
};
```

### Evidence Upload
```javascript
const uploadEvidence = async (file) => {
  const upload = await pinata.upload.public
    .file(file)
    .name(`milestone-evidence-${Date.now()}`);
    
  return upload.cid;
};
```

---

## Ponder GraphQL Queries

### Essential Queries for MVP

#### 1. User Dashboard Data
```graphql
query GetUserDashboard($userAddress: String!) {
  # All user goals
  goalCreateds(where: { owner: $userAddress }, orderBy: timestamp, orderDirection: desc) {
    goalId
    petTokenId
    title
    stakeAmount
    durationDays
    petName
    petType
    totalMilestones
    endTime
    timestamp
  }
  
  # Goal completions
  goalCompleteds(where: { owner: $userAddress }) {
    goalId
    bonusXP
    stakeReward
    completionTime
    wasEarlyCompletion
    timestamp
  }
  
  # Goal failures
  goalFaileds(where: { owner: $userAddress }) {
    goalId
    milestonesCompleted
    totalMilestones
    stakeLost
    failureReason
    timestamp
  }
}
```

#### 2. Goal Progress & Milestones
```graphql
query GetGoalProgress($goalId: String!) {
  # Goal details
  goalCreateds(where: { goalId: $goalId }) {
    goalId
    owner
    title
    stakeAmount
    totalMilestones
    petTokenId
    endTime
  }
  
  # All milestones for this goal
  milestoneCreateds(where: { goalId: $goalId }, orderBy: timestamp) {
    milestoneId
    goalId
    description
    timestamp
  }
  
  # Milestone submissions
  milestoneSubmitteds(where: { goalId: $goalId }, orderBy: timestamp) {
    milestoneId
    submitter
    evidenceIPFS
    timestamp
  }
  
  # Completed milestones
  milestoneCompleteds(where: { goalId: $goalId }, orderBy: timestamp) {
    milestoneId
    xpAwarded
    milestonesCompleted
    totalMilestones
    progressPercentage
    petMetadataIPFS
    timestamp
  }
}
```

#### 3. Pet Evolution History
```graphql
query GetPetEvolution($tokenId: String!) {
  # Pet creation
  petMinteds(where: { tokenId: $tokenId }) {
    tokenId
    owner
    goalId
    petType
    stage
    level
    name
    metadataIPFS
    timestamp
  }
  
  # Evolution events
  petEvolveds(where: { tokenId: $tokenId }, orderBy: timestamp) {
    tokenId
    goalId
    fromStage
    toStage
    milestonesCompleted
    totalExperience
    newMetadataIPFS
    timestamp
  }
  
  # Experience gains
  experienceGaineds(where: { tokenId: $tokenId }, orderBy: timestamp) {
    tokenId
    experienceAmount
    newTotalExp
    oldLevel
    newLevel
    reason
    timestamp
  }
}
```

#### 4. Validation Status
```graphql
query GetValidationStatus($milestoneId: String!) {
  # Validation request
  validationRequesteds(where: { milestoneId: $milestoneId }) {
    milestoneId
    submitter
    evidenceIPFS
    goalStakeAmount
    requiredValidators
    assignedValidators
    deadline
    timestamp
  }
  
  # Validator submissions
  validationSubmitteds(where: { milestoneId: $milestoneId }, orderBy: timestamp) {
    milestoneId
    validator
    approved
    comment
    currentApprovals
    currentRejections
    timestamp
  }
  
  # Resolution
  validationResolveds(where: { milestoneId: $milestoneId }) {
    milestoneId
    status
    totalApprovals
    totalRejections
    validators
    votes
    timestamp
  }
}
```

### Real-time Subscriptions
```graphql
subscription UserActivity($userAddress: String!) {
  # New milestones completed
  milestoneCompleteds(where: { goalOwner: $userAddress }) {
    goalId
    milestoneId
    xpAwarded
    milestonesCompleted
    progressPercentage
    timestamp
  }
  
  # Pet evolutions
  petEvolveds(where: { owner: $userAddress }) {
    tokenId
    goalId
    fromStage
    toStage
    milestonesCompleted
    timestamp
  }
  
  # Goal completions
  goalCompleteds(where: { owner: $userAddress }) {
    goalId
    bonusXP
    stakeReward
    timestamp
  }
}
```

---

## Frontend Integration

### Key React Hooks

#### 1. Goal Creation Hook
```javascript
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';

export const useCreateGoal = () => {
  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  const createGoal = async (goalData) => {
    try {
      // Upload metadata first
      const metadataIPFS = await uploadPetMetadata(goalData);
      
      // Create goal
      await writeContract({
        address: CONTRACTS.PAT_GOAL_MANAGER,
        abi: PAT_GOAL_MANAGER_ABI,
        functionName: 'createGoalWithMilestones',
        args: [
          goalData.title,
          parseEther(goalData.stakeAmount),
          goalData.durationDays,
          goalData.petName,
          goalData.petType,
          metadataIPFS,
          goalData.milestoneDescriptions
        ]
      });
    } catch (error) {
      console.error('Goal creation failed:', error);
      throw error;
    }
  };

  return { createGoal, isConfirming };
};
```

#### 2. User Dashboard Hook
```javascript
import { useQuery } from '@apollo/client';

export const useUserDashboard = (userAddress) => {
  const { data, loading, error } = useQuery(GET_USER_DASHBOARD, {
    variables: { userAddress },
    pollInterval: 5000 // Poll every 5 seconds
  });

  const goals = data?.goalCreateds || [];
  const completedGoals = data?.goalCompleteds || [];
  const failedGoals = data?.goalFaileds || [];

  return {
    goals,
    completedGoals,
    failedGoals,
    loading,
    error,
    stats: {
      total: goals.length,
      completed: completedGoals.length,
      failed: failedGoals.length,
      active: goals.length - completedGoals.length - failedGoals.length
    }
  };
};
```

#### 3. Goal Progress Hook
```javascript
export const useGoalProgress = (goalId) => {
  const { data } = useQuery(GET_GOAL_PROGRESS, {
    variables: { goalId },
    pollInterval: 3000
  });

  const goal = data?.goalCreateds?.[0];
  const milestones = data?.milestoneCreateds || [];
  const completed = data?.milestoneCompleteds || [];

  return {
    goal,
    milestones: milestones.map(m => ({
      ...m,
      isCompleted: completed.some(c => c.milestoneId === m.milestoneId),
      completedData: completed.find(c => c.milestoneId === m.milestoneId)
    })),
    progress: {
      completed: completed.length,
      total: milestones.length,
      percentage: milestones.length > 0 ? (completed.length / milestones.length) * 100 : 0
    }
  };
};
```

### Evolution System Integration
```javascript
// Evolution helper functions
export const getEvolutionStage = (milestonesCompleted) => {
  if (milestonesCompleted >= 4) return { stage: 'ADULT', name: 'Adult', description: 'A fully evolved companion with mastered abilities' };
  if (milestonesCompleted >= 2) return { stage: 'BABY', name: 'Baby', description: 'A young companion learning and growing with each milestone' };
  return { stage: 'EGG', name: 'Egg', description: 'A mysterious egg filled with potential, waiting to hatch' };
};

export const getEvolutionProgress = (milestonesCompleted) => {
  const totalMilestones = 4;
  const percentage = (milestonesCompleted / totalMilestones) * 100;
  
  return {
    percentage,
    nextEvolution: milestonesCompleted < 2 ? 'Baby at 2 milestones' :
                   milestonesCompleted < 4 ? 'Adult at 4 milestones' : 'Fully evolved!',
    milestonesUntilNext: milestonesCompleted < 2 ? 2 - milestonesCompleted :
                        milestonesCompleted < 4 ? 4 - milestonesCompleted : 0
  };
};

// Pet type helper functions
export const getPetTypeName = (petType) => {
  const types = ["Dragon", "Cat", "Plant"];
  return types[petType] || "Unknown";
};

export const getPetTypeKey = (petType) => {
  const keys = ["DRAGON", "CAT", "PLANT"];
  return keys[petType] || "UNKNOWN";
};

export const getPetElement = (petType) => {
  const elements = ["Fire", "Earth", "Nature"];
  return elements[petType] || "Unknown";
};

export const getPetRarity = (petType) => {
  const rarities = ["Epic", "Common", "Rare"];
  return rarities[petType] || "Unknown";
};

// Evolution animation trigger
export const useEvolutionAnimation = () => {
  const [showEvolution, setShowEvolution] = useState(false);
  const [evolutionData, setEvolutionData] = useState(null);

  const triggerEvolution = (fromStage, toStage, petType) => {
    setEvolutionData({ fromStage, toStage, petType });
    setShowEvolution(true);
  };

  return { showEvolution, evolutionData, triggerEvolution, setShowEvolution };
};
```

---

## Event Handling & Real-time Updates

### Contract Event Listeners
```javascript
import { useWatchContractEvent } from 'wagmi';

// Watch for milestone completions
export const useMilestoneEvents = (userAddress) => {
  useWatchContractEvent({
    address: CONTRACTS.PAT_GOAL_MANAGER,
    abi: PAT_GOAL_MANAGER_ABI,
    eventName: 'MilestoneCompleted',
    args: { goalOwner: userAddress },
    onLogs: (logs) => {
      logs.forEach(log => {
        const { goalId, milestonesCompleted, progressPercentage } = log.args;
        
        // Show progress update
        toast.success(`Milestone completed! Progress: ${progressPercentage}%`);
        
        // Check for evolution
        if (milestonesCompleted === 2) {
          triggerEvolution('EGG', 'BABY');
        } else if (milestonesCompleted === 4) {
          triggerEvolution('BABY', 'ADULT');
        }
      });
    }
  });
};

// Watch for pet evolutions
export const usePetEvolutionEvents = (userAddress) => {
  useWatchContractEvent({
    address: CONTRACTS.PAT_NFT,
    abi: PAT_NFT_ABI,
    eventName: 'PetEvolved',
    args: { owner: userAddress },
    onLogs: (logs) => {
      logs.forEach(log => {
        const { tokenId, fromStage, toStage } = log.args;
        
        // Show evolution celebration
        showEvolutionCelebration(fromStage, toStage);
        
        // Update pet display
        refetchPetData();
      });
    }
  });
};
```

---

## Error Handling

### Transaction Error Handler
```javascript
export const handleTransactionError = (error, operation) => {
  console.error(`${operation} failed:`, error);
  
  if (error.message.includes('User rejected')) {
    toast.error('Transaction cancelled by user');
  } else if (error.message.includes('insufficient funds')) {
    toast.error('Insufficient funds for transaction');
  } else if (error.message.includes('TooManyMilestones')) {
    toast.error('Maximum 4 milestones allowed per goal');
  } else if (error.message.includes('InvalidStake')) {
    toast.error('Invalid stake amount');
  } else {
    toast.error(`${operation} failed: ${error.shortMessage || error.message}`);
  }
};
```

### Validation Helpers
```javascript
export const validateGoalCreation = (goalData) => {
  const errors = [];
  
  if (!goalData.title.trim()) errors.push('Goal title is required');
  if (!goalData.petName.trim()) errors.push('Pet name is required');
  if (goalData.milestoneDescriptions.length === 0) errors.push('At least 1 milestone required');
  if (goalData.milestoneDescriptions.length > 4) errors.push('Maximum 4 milestones allowed');
  if (parseFloat(goalData.stakeAmount) <= 0) errors.push('Stake amount must be greater than 0');
  
  return errors;
};
```

---

## Quick Reference

### Evolution System
| Milestones | Stage | Description |
|------------|-------|-------------|
| 0-1 | Egg | A mysterious egg filled with potential |
| 2-3 | Baby | A young companion learning and growing |
| 4 | Adult | A fully evolved companion with mastered abilities |

### Pet Types
| Type | Value | Name | Element | Rarity |
|------|-------|------|---------|---------|
| DRAGON | 0 | Dragon | Fire | Epic |
| CAT | 1 | Cat | Earth | Common |
| PLANT | 2 | Plant | Nature | Rare |

### Key Constants
- **Max milestones per goal**: 4
- **XP per milestone**: 25
- **Completion bonus**: 100 XP
- **Evolution triggers**: 2 milestones (Baby), 4 milestones (Adult)
- **Min validator stake**: 50 PAT

### MVP Priority Order
1. ✅ Goal creation with milestones
2. ✅ Pet metadata generation & upload
3. ✅ Dashboard with goal progress
4. ✅ Milestone submission
5. ✅ Evolution animations
6. ✅ Validation system (admin for MVP)
7. ⏳ Community validation (post-MVP)

---

## Testing & Debugging

### Contract Verification
```javascript
// Test contract connections
const testContracts = async () => {
  try {
    const evolution = await patNFT.getEvolutionThresholds();
    console.log('Evolution thresholds:', evolution); // Should be [2, 4, 25, 100]
    
    const balance = await patToken.balanceOf(userAddress);
    console.log('PAT balance:', formatEther(balance));
    
    return { success: true };
  } catch (error) {
    console.error('Contract test failed:', error);
    return { success: false, error };
  }
};
```

### Common Issues & Solutions
1. **Metadata not loading**: Check Pinata gateway configuration and JWT token
2. **Evolution not triggering**: Verify milestone completion count (2 for Baby, 4 for Adult)
3. **Transaction fails**: Check PAT token approval and balance
4. **GraphQL errors**: Confirm Ponder indexer is synced
5. **Pet images not showing**: Verify Next.js image domains configuration
6. **Pinata upload fails**: Check JWT token permissions and account quota

### Environment Variables Required
```env
# Pinata Configuration
NEXT_PUBLIC_PINATA_JWT=your_pinata_jwt_token
NEXT_PUBLIC_PAT_PET_PINATA_GATEWAY=https://your-gateway.mypinata.cloud

# Contract Addresses (update with deployed addresses)
NEXT_PUBLIC_PAT_TOKEN_ADDRESS=0x...
NEXT_PUBLIC_PAT_GOAL_MANAGER_ADDRESS=0x...
NEXT_PUBLIC_PAT_NFT_ADDRESS=0x...
NEXT_PUBLIC_PAT_VALIDATION_SYSTEM_ADDRESS=0x...
NEXT_PUBLIC_PAT_TREASURY_MANAGER_ADDRESS=0x...
```

Remember: Keep it simple for MVP! Focus on core goal creation → milestone completion → pet evolution flow. 🚀