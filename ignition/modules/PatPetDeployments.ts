import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PatPetModule = buildModule("PetPatModule", (m) => {
  // =============================================================================
  // 🎯 PET PAT DEPLOYMENT MODULE
  // =============================================================================
  
  console.log("🚀 Starting Pet Pat deployment...");

  // =============================================================================
  // STEP 1: DEPLOY CORE TOKEN
  // =============================================================================
  console.log("📝 Step 1: Deploying PATToken...");
  
  const patToken = m.contract("PATToken", [], {
    id: "PATToken",
  });

  // =============================================================================
  // STEP 2: DEPLOY TREASURY MANAGER
  // =============================================================================
  console.log("💰 Step 2: Deploying PatTreasuryManager...");
  
  const treasuryManager = m.contract("PatTreasuryManager", [patToken], {
    id: "PatTreasuryManager",
  });

  // =============================================================================
  // STEP 3: DEPLOY VALIDATION SYSTEM
  // =============================================================================
  console.log("✅ Step 3: Deploying PatValidationSystem...");
  
  const validationSystem = m.contract("PatValidationSystem", [
    patToken,
    treasuryManager,
  ], {
    id: "PatValidationSystem",
  });

  // =============================================================================
  // STEP 4: DEPLOY PET NFT
  // =============================================================================
  console.log("🐱 Step 4: Deploying PatNFT...");
  
  const petNFT = m.contract("PatNFT", [], {
    id: "PatNFT",
  });

  // =============================================================================
  // STEP 5: DEPLOY GOAL MANAGER
  // =============================================================================
  console.log("🎯 Step 5: Deploying PatGoalManager...");
  
  const goalManager = m.contract("PatGoalManager", [
    patToken,
    treasuryManager,
    validationSystem,
    petNFT,
  ], {
    id: "PatGoalManager",
  });

  // =============================================================================
  // STEP 6: CONFIGURE TOKEN AUTHORIZATIONS
  // =============================================================================
  console.log("🔐 Step 6: Setting up token authorizations...");
  
  // Add TreasuryManager as authorized minter
  m.call(patToken, "addAuthorizedMinter", [treasuryManager], {
    id: "AddTreasuryMinter",
  });

  // Add TreasuryManager as authorized burner
  m.call(patToken, "addAuthorizedBurner", [treasuryManager], {
    id: "AddTreasuryBurner",
  });

  // =============================================================================
  // STEP 7: CONFIGURE TREASURY AUTHORIZATIONS
  // =============================================================================
  console.log("💎 Step 7: Setting up treasury authorizations...");
  
  // Add GoalManager as authorized contract for treasury
  m.call(treasuryManager, "addAuthorizedContract", [goalManager], {
    id: "AddGoalManagerToTreasury",
  });

  // =============================================================================
  // STEP 8: CONFIGURE VALIDATION AUTHORIZATIONS
  // =============================================================================
  console.log("🛡️ Step 8: Setting up validation authorizations...");
  
  // Add GoalManager as authorized contract for validation
  m.call(validationSystem, "addAuthorizedContract", [goalManager], {
    id: "AddGoalManagerToValidation",
  });

  // =============================================================================
  // STEP 9: CONFIGURE NFT AUTHORIZATIONS
  // =============================================================================
  console.log("🎨 Step 9: Setting up NFT authorizations...");
  
  // Add GoalManager as authorized contract for NFT
  m.call(petNFT, "setAuthorizedContract", [goalManager, true], {
    id: "AddGoalManagerToNFT",
  });

  // =============================================================================
  // STEP 10: FINAL CONFIGURATION
  // =============================================================================
  console.log("⚙️ Step 10: Final configuration...");

  // Return all deployed contracts for use
  return {
    patToken,
    treasuryManager,
    validationSystem,
    petNFT,
    goalManager,
  };
});

export default PatPetModule;